||| An HTTP/1.1 client.
|||
||| Two layers:
|||
|||  * `request` sends one request on a connection (`Network.HTTP.Connection`)
|||    and reads the head of the response, whose body is then read with
|||    `readChunk` or `readAll`; the caller makes the connection (over any
|||    `Transport`) and decides what to do with it afterwards.
|||  * A `Client` takes URLs: it resolves the host, connects with a timeout,
|||    sends `Host` (and `User-Agent` if configured), keeps persistent
|||    connections in a pool per host (closed after an idle timeout), follows
|||    redirects up to a limit, and bounds each request with a deadline.
|||    `fetch` reads the whole response body (up to a limit); `withResponse`
|||    gives the body to a function as a stream.
|||
||| ```idris
||| main : IO ()
||| main = do
|||   c <- newClient defaultClientConfig
|||   Right r <- httpGet c "http://127.0.0.1:8080/hello"
|||     | Left e => putStrLn (show e)
|||   putStrLn (show r.status.code ++ " " ++ toStringLossy r.body)
||| ```
|||
||| Only `http://` URLs work unless a TLS connector is configured
||| (`tlsConnect`): there is no TLS in this library.  There are no cookies,
||| no proxies and no compression; a request goes to the host of its URL.
module Network.HTTP.Client

import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal
import Data.IORef
import Data.List
import Data.Maybe
import Network.HTTP.Internal.Bytes
import public Network.HTTP.Connection
import public Network.HTTP.Parser
import public Network.HTTP.Transport
import public Network.HTTP.Types
import public Network.HTTP2.Config
import Network.HTTP2.Connection
import Network.URI
import System.Concurrency

%default covering

--------------------------------------------------------------------------
-- Requests and responses
--------------------------------------------------------------------------

||| The body of a request.
public export
data RequestBody : Type where
  ||| None.
  NoRequestBody : RequestBody
  ||| These bytes (with `Content-Length`).
  RequestBytes : ByteString -> RequestBody
  ||| Bytes written by a function, a piece at a time (`writeBody`), of a
  ||| length declared in advance (`Content-Length`) or in the chunked coding.
  RequestStream : (length : Maybe Int) -> (BodyWriter -> IO ()) -> RequestBody

||| A request to send on a connection.
public export
record ClientRequest where
  constructor MkClientRequest
  method : Method
  ||| The request target (`/path?query`).
  target : ByteString
  ||| The fields: `Host` must be there (HTTP/1.1 requires it); the client
  ||| writes `Content-Length` or `Transfer-Encoding` itself and drops those
  ||| given here.
  headers : Headers
  body : RequestBody

||| The head of a response, and its body to read.
public export
record ClientResponse where
  constructor MkClientResponse
  version : Version
  status : Status
  headers : Headers
  body : BodyReader
  ||| Can the connection carry another request once the body has been read
  ||| to its end?
  reusable : Bool

crlf : ByteString
crlf = "\r\n"

colonSpace : ByteString
colonSpace = ": "

http11Line : ByteString
http11Line = " HTTP/1.1\r\n"

contentLengthColon : ByteString
contentLengthColon = "Content-Length: "

chunkedLine : ByteString
chunkedLine = "Transfer-Encoding: chunked\r\n"

closeToken : ByteString
closeToken = "close"

isFramingField : Header -> Bool
isFramingField h = eqLower h.name hContentLength || eqLower h.name hTransferEncoding

fieldsSize : List Header -> Int -> Int
fieldsSize [] acc = acc
fieldsSize (h :: hs) acc = fieldsSize hs (acc + lengthInt h.name + lengthInt h.value + 4)

putFields : Buffer -> Int -> List Header -> IO Int
putFields b at [] = pure at
putFields b at (h :: hs) = do
  at <- putFields b at hs
  if isFramingField h then pure at else do
    at <- putBytes b at h.name
    at <- putBytes b at colonSpace
    at <- putBytes b at h.value
    putBytes b at crlf

data Framing = FLength Int | FChunked | FNone

putFraming : Buffer -> Int -> Framing -> IO Int
putFraming b at (FLength n) = do
  at <- putBytes b at contentLengthColon
  at <- putDecimal b at n
  putBytes b at crlf
putFraming b at FChunked = putBytes b at chunkedLine
putFraming b at FNone = pure at

-- Does the method have a body by its meaning (so that an empty one is
-- sent as `Content-Length: 0`)?
expectsBody : Method -> Bool
expectsBody POST = True
expectsBody PUT = True
expectsBody PATCH = True
expectsBody _ = False

visibleASCII : ByteString -> Int -> Int -> Bool
visibleASCII bs i n =
  if i >= n then True
  else let w = unsafeIndex bs i in
       if w > 32 && w < 127 then visibleASCII bs (i + 1) n else False

||| Send a request: the head, then the body.  The head and a body of bytes
||| go out with one system call when they fit.  `OtherError` if a field is
||| not valid (a CR or LF in a value would inject fields), or if the method
||| or target has bytes that do not belong there.
export
writeRequest : Conn -> ClientRequest -> (deadline : Int) -> IO (Either HttpError ())
writeRequest c r dl = do
  let fields = headersToListRev r.headers
  case invalidHeader r.headers of
    Just h => pure (Left (OtherError ("request field not valid: " ++ show h.name)))
    Nothing =>
      if not (isValidHeaderName (methodBytes r.method)) || lengthInt r.target == 0
         || not (visibleASCII r.target 0 (lengthInt r.target))
        then pure (Left (OtherError "request method or target not valid"))
        else do
          let fr = case r.body of
                     NoRequestBody => if expectsBody r.method then FLength 0 else FNone
                     RequestBytes bs => if lengthInt bs == 0 && not (expectsBody r.method)
                                           then FNone else FLength (lengthInt bs)
                     RequestStream (Just n) _ => FLength n
                     RequestStream Nothing _ => FChunked
          let size = fieldsSize fields 0 + lengthInt (methodBytes r.method) + lengthInt r.target + 80
          b <- headBuffer c size
          at <- putBytes b 0 (methodBytes r.method)
          at <- putByte b at 32
          at <- putBytes b at r.target
          at <- putBytes b at http11Line
          at <- putFields b at fields
          at <- putFraming b at fr
          at <- putBytes b at crlf
          case r.body of
            NoRequestBody => sendHeadAndBody c b at Data.ByteString.empty dl
            RequestBytes bs => sendHeadAndBody c b at bs dl
            RequestStream len f => do
              Right () <- sendHeadAndBody c b at Data.ByteString.empty dl
                | Left e => pure (Left e)
              w <- case len of
                     Just n => rawWriter c (Just n) (pure dl)
                     Nothing => chunkedWriter c (pure dl)
              f w
              finishBody w

-- Read heads until one that is not an interim response (1xx other than
-- 101).
readFinalHead : Conn -> Limits -> Int -> IO (Either HttpError ResponseHead)
readFinalHead c lim dl = do
  Right h <- readHead c (responseParser lim) dl 0
    | Left IdleTimeout => pure (Left TimedOut)
    | Left e => pure (Left e)
  if h.status.code >= 100 && h.status.code < 200 && h.status.code /= 101
     then readFinalHead c lim dl
     else pure (Right h)

||| Read the head of the response to a request with a method, before the
||| deadline (which also bounds each read of the body).  Interim responses
||| (`100 Continue`, `103 Early Hints`) are skipped.  The body is framed as
||| RFC 9112 says (no body for `HEAD`, 204 and 304; until the end of the
||| connection when there is no framing).  `requestKeepsAlive` says whether
||| the request let the connection go on (no `Connection: close`).
export
readResponse : Conn -> Limits -> (requestMethod : Method) -> (requestKeepsAlive : Bool) ->
               (deadline : Int) -> IO (Either HttpError ClientResponse)
readResponse c lim m keep dl = do
  Right h <- readFinalHead c lim dl
    | Left e => pure (Left e)
  case responseFraming m h of
    Left e => pure (Left (BadHead e))
    Right fr => do
      body <- bodyReader c fr (-1) (pure dl) Nothing
      let reusable = keep && h.status.code /= 101 && fr /= UntilClose
                     && isPersistent h.version h.headers
      pure (Right (MkClientResponse h.version h.status h.headers body reusable))

||| Send a request on a connection and read the head of its response
||| (`writeRequest`, then `readResponse` with the default limits).
export
request : Conn -> ClientRequest -> (deadline : Int) -> IO (Either HttpError ClientResponse)
request c r dl = do
  Right () <- writeRequest c r dl
    | Left e => pure (Left e)
  readResponse c defaultLimits r.method (isPersistent http11 r.headers) dl

--------------------------------------------------------------------------
-- URLs
--------------------------------------------------------------------------

||| Where a URL leads.
public export
record Target where
  constructor MkTarget
  ||| `https`?
  secure : Bool
  ||| The host to connect to: a name, or a numeric address (an IPv6 one
  ||| without its brackets).
  host : String
  port : Int
  ||| The value of the `Host` field: the authority of the URL without user
  ||| information.
  hostField : ByteString
  ||| The request target: the path (`/` if empty) and the query.
  path : ByteString
  ||| The URL, for resolving relative redirects.
  uri : URI

httpBS, httpsBS : ByteString
httpBS = "http"
httpsBS = "https"

hostText : Host -> Either HttpError String
hostText (RegName n) = case percentDecode n of
                         Just d => Right (toStringLossy d)
                         Nothing => Left (BadURL "bad host")
hostText (IPv4 a) = Right (toStringLossy a)
hostText (IPv6 a) = Right (toStringLossy a)
hostText (IPFuture _) = Left (BadURL "IPvFuture host")

hostBytes : Host -> ByteString
hostBytes (RegName n) = n
hostBytes (IPv4 a) = a
hostBytes (IPv6 a) = "[" <+> a <+> "]"
hostBytes (IPFuture a) = "[" <+> a <+> "]"

hostFieldOf : Host -> Maybe Int -> ByteString
hostFieldOf h Nothing = hostBytes h
hostFieldOf h (Just n) = hostBytes h <+> ":" <+> Data.ByteString.fromString (show n)

questionMark, slashOnly : ByteString
questionMark = "?"
slashOnly = "/"

targetOf : ByteString -> Maybe ByteString -> ByteString
targetOf p q =
  let p' = if lengthInt p == 0 then slashOnly else p in
  case q of
    Nothing => p'
    Just q' => p' <+> questionMark <+> q'

||| The target of an absolute URI.
export
uriTarget : URI -> Either HttpError Target
uriTarget u = do
  scheme <- maybe (Left (BadURL "no scheme")) Right u.scheme
  secure <- if eqLower scheme httpBS then Right False
            else if eqLower scheme httpsBS then Right True
            else Left (UnsupportedScheme ("scheme " ++ toStringLossy scheme ++ " is not supported (only http and https)"))
  a <- maybe (Left (BadURL "no host")) Right u.authority
  h <- hostText a.host
  when (h == "") $ Left (BadURL "empty host")
  let port = fromMaybe (if secure then 443 else 80) a.port
  let path = targetOf u.path u.query
  pure (MkTarget secure h port (hostFieldOf a.host a.port) path ({ fragment := Nothing } u))

||| The target of a URL (`http://host:port/path?query`).
export
parseURL : String -> Either HttpError Target
parseURL s = case parseURI (fromString s) of
  Left e => Left (BadURL (show e))
  Right u => uriTarget u

--------------------------------------------------------------------------
-- Clients
--------------------------------------------------------------------------

||| Makes a TLS transport over a connected socket, for a host name and a
||| port, before the deadline; `Left` with a message if the handshake fails
||| (the connector closes the socket then).
public export
TLSConnector : Type
TLSConnector = (host : String) -> (port : Int) -> AsyncSocket -> (deadline : Int) ->
               IO (Either String Transport)

||| The configuration of a client.  Times are in milliseconds; 0 is no
||| limit.
public export
record ClientConfig where
  constructor MkClientConfig
  ||| For resolving the host and connecting.
  connectTimeout : Int
  ||| For a whole request (with its redirects), from the start to the end
  ||| of the response body.
  requestTimeout : Int
  ||| How many redirects to follow (0 to return them).
  maxRedirects : Int
  ||| The largest response body that `fetch` reads.
  maxResponseSize : Int
  ||| How long an idle connection stays in the pool.
  idleTimeout : Int
  ||| The most idle connections kept per host.
  maxIdlePerHost : Int
  ||| The size of the scratch buffer of each connection.
  bufferSize : Int
  ||| The limits of the parser of response heads.
  limits : Limits
  ||| The value of `User-Agent`, if one is to be sent (when the request has
  ||| none).
  userAgent : Maybe ByteString
  ||| How to make connections to `https` URLs: none here (see the TLS
  ||| library).  A connection for which the connector agreed on `h2` with
  ||| ALPN (`transportProtocol`) speaks HTTP/2.
  tlsConnect : Maybe TLSConnector
  ||| The settings and limits of HTTP/2 connections.
  http2 : H2Config
  ||| Speak HTTP/2 to `http://` URLs without asking (prior knowledge):
  ||| only for servers that are known to take it.
  http2PriorKnowledge : Bool

||| 10 s to connect, 60 s per request, 10 redirects, responses up to 64 MiB,
||| 90 s of idle time and 8 idle connections per host in the pool, a
||| buffer of 4 KiB, the default limits, no `User-Agent`, no TLS, the
||| default settings of HTTP/2 and no HTTP/2 for `http://` URLs.
export
defaultClientConfig : ClientConfig
defaultClientConfig =
  MkClientConfig 10000 60000 10 67108864 90000 8 4096 defaultLimits Nothing Nothing
                 defaultH2Config False

-- An idle connection of the pool: its key (host and port), the connection,
-- and since when it is idle.
record Idle where
  constructor MkIdle
  key : String
  conn : Conn
  since : Int

||| A client: a configuration and a pool of connections (HTTP/1.1 ones,
||| each carrying a request at a time, and HTTP/2 ones, one per host,
||| shared by the requests to it).  It may be used by several threads at a
||| time.
export
record Client where
  constructor MkClient
  config : ClientConfig
  lock : Mutex
  pool : IORef (List Idle)
  opened : IORef Int
  h2pool : IORef (List (String, H2Conn))
  -- the hosts known to speak HTTP/2, and those that a thread connects to
  -- now (the others wait for its connection, to share it)
  h2hosts : IORef (List String)
  connecting : IORef (List String)
  connected : Condition

||| A client with an empty pool.
export
newClient : ClientConfig -> IO Client
newClient cfg = [| MkClient (pure cfg) makeMutex (newIORef []) (newIORef 0) (newIORef [])
                            (newIORef []) (newIORef []) makeCondition |]

||| The number of connections that the client has opened.
export
connectionsOpened : Client -> IO Int
connectionsOpened c = readIORef c.opened

||| Close the idle connections of the pool.
export
closeIdle : Client -> IO ()
closeIdle c = do
  mutexAcquire c.lock
  conns <- readIORef c.pool
  writeIORef c.pool []
  h2s <- readIORef c.h2pool
  writeIORef c.h2pool []
  mutexRelease c.lock
  traverse_ (\i => closeConn i.conn) conns
  traverse_ (\(_, h) => closeH2 h) h2s

poolKey : Target -> String
poolKey t = (if t.secure then "https:" else "http:") ++ t.host ++ ":" ++ show t.port

-- An idle connection to a host, if the pool has one that is not too old
-- (the old ones are closed).
takeIdle : Client -> String -> IO (Maybe Conn)
takeIdle c key = do
  t <- now
  let limit = c.config.idleTimeout * 1000000
  mutexAcquire c.lock
  conns <- readIORef c.pool
  let (old, fresh) = partition (\i => limit > 0 && t - i.since > limit) conns
  let (mine, others) = break (\i => i.key == key) fresh
  case others of
    (i :: rest) => do
      writeIORef c.pool (mine ++ rest)
      mutexRelease c.lock
      traverse_ (\o => closeConn o.conn) old
      pure (Just i.conn)
    [] => do
      writeIORef c.pool fresh
      mutexRelease c.lock
      traverse_ (\o => closeConn o.conn) old
      pure Nothing

-- Put a connection back in the pool (or close it if the host has enough).
putIdle : Client -> String -> Conn -> IO ()
putIdle c key conn = do
  t <- now
  mutexAcquire c.lock
  conns <- readIORef c.pool
  if length (filter (\i => i.key == key) conns) >= cast c.config.maxIdlePerHost
     then do mutexRelease c.lock
             closeConn conn
     else do writeIORef c.pool (MkIdle key conn t :: conns)
             mutexRelease c.lock

-- Is a connection taken from the pool still usable: no byte and no end of
-- stream waiting on it (a server that closed it, or sent something it was
-- not asked for)?  A read with a deadline in the past answers at once.
stillOpen : Conn -> IO Bool
stillOpen conn = do
  p <- pendingBytes conn
  if lengthInt p > 0 then pure False else do
    r <- readSome conn 0
    case r of
      Left TimedOut => pure True
      _ => pure False

-- A connection that carries requests to a host: an HTTP/1.1 one (and
-- whether it came from the pool), or an HTTP/2 one.
data Carrier = H1 Conn | H2 H2Conn H2Stream

-- An HTTP/2 connection to a host that can take another request, from
-- the pool (those that cannot are dropped from it).
takeH2 : Client -> String -> IO (Maybe H2Conn)
takeH2 c key = do
  mutexAcquire c.lock
  hs <- readIORef c.h2pool
  ok <- filterM (\(_, h) => h2Usable h) hs
  writeIORef c.h2pool ok
  mutexRelease c.lock
  pure (lookup key ok)
  where
    filterM : (a -> IO Bool) -> List a -> IO (List a)
    filterM f [] = pure []
    filterM f (x :: xs) = do
      k <- f x
      rest <- filterM f xs
      pure (if k then x :: rest else rest)

connectTo : Client -> Target -> (deadline : Int) -> IO (Either HttpError (Either Conn H2Conn))
connectTo c t tdl = do
  cd <- deadlineAfterMs c.config.connectTimeout
  let d = earlierDeadline cd tdl
  Right s <- connectHost t.host t.port (if d < 0 then Nothing else Just d)
    | Left Timeout => pure (Left TimedOut)
    | Left e => pure (Left (NetFailure e))
  ignore (setOption s NoDelay 1)
  modifyIORef c.opened (+ 1)
  tr <- the (IO (Either HttpError Transport)) $
        if not t.secure then pure (Right (socketTransport s Nothing)) else
          case c.config.tlsConnect of
            Nothing => do
              ignore (close s)
              pure (Left (UnsupportedScheme "https needs a TLS transport: set tlsConnect of the ClientConfig (see the tls library)"))
            Just tls => do
              Right tr <- tls t.host t.port s d
                | Left msg => pure (Left (OtherError ("TLS: " ++ msg)))
              pure (Right tr)
  case tr of
    Left e => pure (Left e)
    Right tr => do
      conn <- newConn tr c.config.bufferSize
      if transportProtocol tr == Just h2Protocol || (not t.secure && c.config.http2PriorKnowledge)
         then do
           let cfg = c.config
           h <- startClient cfg.http2 conn cfg.requestTimeout cfg.requestTimeout cfg.idleTimeout (\_ => pure ())
           mutexAcquire c.lock
           modifyIORef c.h2pool ((poolKey t, h) ::)
           hosts <- readIORef c.h2hosts
           when (not (elem (poolKey t) hosts)) $ writeIORef c.h2hosts (poolKey t :: hosts)
           mutexRelease c.lock
           pure (Right (Right h))
         else pure (Right (Left conn))

-- A connection to a target: an HTTP/2 one if there is one, an idle one
-- from the pool if there is one that is still open (and whether it was),
-- or a new one.
getConn : Client -> Target -> Int -> IO (Either HttpError (Either (Conn, Bool) H2Conn))
getConn c t tdl = do
  let key = poolKey t
  Nothing <- takeH2 c key
    | Just h => pure (Right (Right h))
  -- (to a host that speaks HTTP/2, one thread connects at a time, and the
  -- others share its connection)
  mutexAcquire c.lock
  hosts <- readIORef c.h2hosts
  let serial = (not t.secure && c.config.http2PriorKnowledge) || elem key hosts
  mine <- if serial then claim key else pure True
  mutexRelease c.lock
  if not mine then getConn c t tdl else
    if serial
      then do
        r <- connectTo c t tdl
        mutexAcquire c.lock
        modifyIORef c.connecting (filter (/= key))
        conditionBroadcast c.connected
        mutexRelease c.lock
        pure (map (either (\x => Left (x, False)) Right) r)
      else h1 key
  where
    -- Claim the connection to a host (lock held): False after waiting for
    -- another thread that had it.
    claim : String -> IO Bool
    claim key = do
      cs <- readIORef c.connecting
      if elem key cs
         then do conditionWait c.connected c.lock
                 cs' <- readIORef c.connecting
                 if elem key cs' then claim key else pure False
         else do writeIORef c.connecting (key :: cs); pure True

    h1 : String -> IO (Either HttpError (Either (Conn, Bool) H2Conn))
    h1 key = do
      Just conn <- takeIdle c key
        | Nothing => map (either (\x => Left (x, False)) Right) <$> connectTo c t tdl
      True <- stillOpen conn
        | False => do closeConn conn; getConn c t tdl
      pure (Right (Left (conn, True)))

hostField, userAgentField : ByteString
hostField = "Host"
userAgentField = "User-Agent"

-- The fields of a request to a target: `Host` and `User-Agent` added.
requestFields : ClientConfig -> Target -> Headers -> Headers
requestFields cfg t hs =
  let hs1 = if hasHeader hHost hs then hs else addHeader hostField t.hostField hs in
  case cfg.userAgent of
    Just ua => if hasHeader hUserAgent hs1 then hs1 else addHeader userAgentField ua hs1
    Nothing => hs1

replayable : RequestBody -> Bool
replayable (RequestStream _ _) = False
replayable _ = True

-- The content-length of a request body, if it has one.
bodyLength : Method -> RequestBody -> Maybe Int
bodyLength m NoRequestBody = if expectsBody m then Just 0 else Nothing
bodyLength m (RequestBytes bs) = if lengthInt bs == 0 && not (expectsBody m) then Nothing else Just (lengthInt bs)
bodyLength m (RequestStream l _) = l

-- Send a request on an HTTP/2 connection and wait for the head of the
-- response.
h2Send : Client -> H2Conn -> Target -> Method -> Headers -> RequestBody -> Int ->
         IO (Either HttpError (H2Stream, ClientResponse))
h2Send c h t m hs body tdl = do
  let hs1 = requestFields c.config t hs
  case invalidHeader hs1 of
    Just bad => pure (Left (OtherError ("request field not valid: " ++ show bad.name)))
    Nothing => do
      let len = bodyLength m body
      let end = case body of
                  RequestStream _ _ => False
                  RequestBytes bs => lengthInt bs == 0
                  NoRequestBody => True
      let fields = [ MkHeaderField ":method" (methodBytes m) False
                   , MkHeaderField ":scheme" (if t.secure then httpsBS else httpBS) False
                   , MkHeaderField ":authority" t.hostField False
                   , MkHeaderField ":path" t.path False ]
                   ++ filter (\f => f.name /= hContentLength) (toFields hs1)
                   ++ maybe [] (\n => [MkHeaderField "content-length" (fromString (show n)) False]) len
      Right s <- openRequest h fields end tdl
        | Left e => pure (Left e)
      -- (a server may answer without reading all of the body: a failure
      -- to send it shows in the response, if there is none)
      ignore $ the (IO (Either HttpError ())) $ case body of
                RequestBytes bs => if lengthInt bs == 0 then pure (Right ()) else sendData h s bs True
                RequestStream l f => do
                  w <- dataWriter h s l
                  f w
                  finishBody w
                NoRequestBody => pure (Right ())
      Right (code, rhs) <- awaitResponse h s tdl
        | Left e => do closeStream h s
                       pure (Left e)
      rb <- streamBody h s
      pure (Right (s, MkClientResponse (MkVersion 2 0) (statusFromCode code) rhs rb True))

-- Send a request to a target and read the head of the response; retried
-- once on a new connection when a connection from the pool turns out to be
-- closed before any byte of the response, or when an HTTP/2 server did not
-- process it (GOAWAY, REFUSED_STREAM), for idempotent methods with a body
-- that can be sent again.
sendOnce : Client -> Target -> Method -> Headers -> RequestBody -> Int ->
           IO (Either HttpError (Carrier, ClientResponse))
sendOnce c t m hs body tdl = go True
  where
    go : Bool -> IO (Either HttpError (Carrier, ClientResponse))
    go mayRetry = do
      Right carrier <- getConn c t tdl
        | Left e => pure (Left e)
      case carrier of
        Right h => do
          r <- h2Send c h t m hs body tdl
          case r of
            Right (s, resp) => pure (Right (H2 h s, resp))
            Left e =>
              if mayRetry && notProcessed e && isIdempotent m && replayable body
                 then go False else pure (Left e)
        Left (conn, reused) => do
          let req = MkClientRequest m t.path (requestFields c.config t hs) body
          let keep = isPersistent http11 req.headers
          w <- writeRequest conn req tdl
          r <- the (IO (Either HttpError ClientResponse)) $ case w of
                 Left e => pure (Left e)
                 Right () => readResponse conn c.config.limits m keep tdl
          case r of
            Right resp => pure (Right (H1 conn, resp))
            Left e => do
              closeConn conn
              let retry = mayRetry && reused && isIdempotent m && replayable body &&
                          (case e of
                             ConnectionClosed => True
                             NetFailure _ => True
                             _ => False)
              if retry then go False else pure (Left e)

-- After a response: back to the pool if the body has ended and the
-- connection can go on, closed otherwise (an HTTP/2 stream is reset if
-- its body has not ended).
release : Client -> Target -> Carrier -> ClientResponse -> IO ()
release c t (H2 h s) resp = closeStream h s
release c t (H1 conn) resp = do
  ended <- bodyEnded resp.body
  if ended && resp.reusable then putIdle c (poolKey t) conn else closeConn conn

closeCarrier : Carrier -> IO ()
closeCarrier (H1 conn) = closeConn conn
closeCarrier (H2 h s) = closeStream h s

-- Done with a response that is not given to the caller: its body (a small
-- one) is read so that the connection can go back to the pool.
discard : Client -> Target -> Carrier -> ClientResponse -> IO ()
discard c t conn resp = do
  ok <- drain resp.body 65536
  if ok then release c t conn resp else closeCarrier conn

isRedirect : Int -> Bool
isRedirect s = s == 301 || s == 302 || s == 303 || s == 307 || s == 308

-- The fields of a request that is redirected to another host lose their
-- credentials; one that becomes a GET loses its content fields.
redirectFields : Bool -> Bool -> Headers -> Headers
redirectFields otherHost toGet hs =
  dropContent toGet (if otherHost then dropCredentials hs else hs)
  where
    dropCredentials : Headers -> Headers
    dropCredentials h = removeHeader hAuthorization (removeHeader hCookie (removeHeader hHost h))
    dropContent : Bool -> Headers -> Headers
    dropContent True h = removeHeader hContentType h
    dropContent False h = h

-- Follow a request (and its redirects) to the response that is not
-- followed further, with its connection and target.
follow : Client -> Target -> Method -> Headers -> RequestBody -> (left : Int) -> (tdl : Int) ->
         IO (Either HttpError (Target, Carrier, ClientResponse))
follow c t m hs body left tdl = do
  Right (conn, resp) <- sendOnce c t m hs body tdl
    | Left e => pure (Left e)
  let code = resp.status.code
  if not (isRedirect code) || c.config.maxRedirects <= 0 then pure (Right (t, conn, resp)) else
    case lookupHeader hLocation resp.headers of
      Nothing => pure (Right (t, conn, resp))
      Just loc => do
        let toGet = code == 303 || ((code == 301 || code == 302) && m == POST)
        -- a stream cannot be sent again
        if not toGet && not (replayable body) then pure (Right (t, conn, resp)) else
          if left <= 0 then do discard c t conn resp; pure (Left TooManyRedirects) else do
            case parseURIReference loc of
              Left e => do closeCarrier conn; pure (Left (BadURL ("redirect: " ++ show e)))
              Right ref => case uriTarget (resolve t.uri ref) of
                Left e => do closeCarrier conn; pure (Left e)
                Right t' => do
                  discard c t conn resp
                  let m' = if toGet && m /= HEAD then GET else m
                  let body' = if toGet then NoRequestBody else body
                  let other = t'.host /= t.host || t'.port /= t.port || t'.secure /= t.secure
                  follow c t' m' (redirectFields other toGet hs) body' (left - 1) tdl

||| Send a request to a URL, following redirects (up to `maxRedirects`), and
||| give the response to a function, which may read its body as a stream
||| (`readChunk`); its deadline is the one of the whole request.  The
||| connection goes back to the pool if the function read the body to its
||| end.
export
withResponse : Client -> Method -> (url : String) -> Headers -> RequestBody ->
               (ClientResponse -> IO a) -> IO (Either HttpError a)
withResponse c m url hs body f = do
  Right t <- pure (parseURL url)
    | Left e => pure (Left e)
  tdl <- deadlineAfterMs c.config.requestTimeout
  Right (t', conn, resp) <- follow c t m hs body c.config.maxRedirects tdl
    | Left e => pure (Left e)
  x <- f resp
  release c t' conn resp
  pure (Right x)

||| A response with its whole body.
public export
record Reply where
  constructor MkReply
  status : Status
  headers : Headers
  body : ByteString
  ||| The URL that gave the response (after redirects).
  url : String

||| Send a request to a URL, following redirects, and read the whole
||| response body (`BodyTooLarge` beyond `maxResponseSize`).
export
fetch : Client -> Method -> (url : String) -> Headers -> RequestBody -> IO (Either HttpError Reply)
fetch c m url hs body = do
  Right t <- pure (parseURL url)
    | Left e => pure (Left e)
  tdl <- deadlineAfterMs c.config.requestTimeout
  Right (t', conn, resp) <- follow c t m hs body c.config.maxRedirects tdl
    | Left e => pure (Left e)
  r <- readAll resp.body c.config.maxResponseSize
  release c t' conn resp
  case r of
    Left e => pure (Left e)
    Right bs => pure (Right (MkReply resp.status resp.headers bs (toStringLossy (renderURI t'.uri))))

||| `GET` a URL (see `fetch`).
export
httpGet : Client -> (url : String) -> IO (Either HttpError Reply)
httpGet c url = fetch c GET url emptyHeaders NoRequestBody

||| `POST` bytes of a content type to a URL (see `fetch`).
export
httpPost : Client -> (url : String) -> (contentType : ByteString) -> ByteString ->
           IO (Either HttpError Reply)
httpPost c url ct bs = fetch c POST url (addHeader "Content-Type" ct emptyHeaders) (RequestBytes bs)
