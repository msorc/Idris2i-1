||| An HTTP/1.1 server: a green thread per connection, persistent
||| connections and pipelining, bodies read and written as wholes or as
||| streams, limits and timeouts, and graceful shutdown.
|||
||| ```idris
||| hello : Request -> IO Response
||| hello req = pure (textResponse statusOK "Hello, world!\n")
|||
||| main : IO ()
||| main = do
|||   Right () <- serve (defaultServerConfig (Inet "127.0.0.1" 8080)) hello
|||     | Left e => putStrLn (show e)
|||   pure ()
||| ```
|||
||| # What the server does for the handler
|||
|||  * It reads and checks the head (`Network.HTTP.Parser`): a malformed or
|||    ambiguous one (the shapes that request smuggling uses) is answered with
|||    the status that the parser gives and the connection is closed; the
|||    handler never sees it.
|||  * It answers `Expect: 100-continue` with `100 Continue` when the handler
|||    starts reading the body (not before: a handler that answers without
|||    reading it does not make the client send it, and the connection is
|||    closed after the response).
|||  * After the handler, it reads what is left of the body (up to
|||    `maxDrain` bytes) so that the next request can be read, or closes the
|||    connection.
|||  * It frames the response: `Content-Length` for a body whose length is
|||    known, the chunked coding for a stream (or the end of the connection
|||    for an HTTP/1.0 client), no body for `HEAD` and for 1xx, 204 and 304;
|||    the framing fields that the handler gives are dropped.  It adds `Date`
|||    (formatted once a second) and, if configured, `Server`, and
|||    `Connection: close` when the connection ends after the response.
|||  * It checks the fields of the response (`isValidHeaderName`,
|||    `isValidHeaderValue`): a response with a field that would inject
|||    others (a CR or LF in a value) is replaced by a 500.
|||
||| # Errors in handlers
|||
||| A handler is an `IO` action, which has no exceptions to catch; a handler
||| that can fail can be written as `Request -> IO (Either String Response)`
||| and made into a `Handler` with `fromEither`, which answers 500 for a
||| `Left` (and logs it).
|||
||| A crash of a handler (`idris_crash`, a missing case of a `partial`
||| function, an access out of a `Buffer`: see `System.Crash`) ends only its
||| request: the handler runs in a crash boundary.  The error log gets the
||| message of the crash (and its backtrace, when backtraces are on), the
||| access log gets the entry of the request, and the server goes on.  Over
||| HTTP/1.1 the request is answered with 500 if no part of the response was
||| sent (else the response is cut short), and the connection is closed;
||| over HTTP/2 the stream is answered with 500 or, if its response had
||| started, reset with `INTERNAL_ERROR`, and the other streams of the
||| connection go on.  A crash in the function of a `StreamBody` or an
||| `UpgradeBody` is caught the same way.  The server never holds a lock of
||| its own while handler code runs.  What a caught crash leaves behind (the
||| memory that the handler held is leaked, a `Mutex` that it held stays
||| held, see `System.Crash`) is the price of going on: `crashesCaught`
||| counts the crashes, for an operator who restarts a server that leaks.
||| On a back end without crash boundaries (`crashBoundaries`), a crash
||| still ends the process.
|||
||| # Threads
|||
||| On the RefC back end the connections are green threads, spread over
||| `IDRIS2_WORKERS` OS threads (one per processor by default).  On Chez and
||| Racket they are OS threads, and a read or a write blocks its thread.
module Network.HTTP.Server

import Data.Buffer
import Data.ByteString
import public Data.ByteString.Builder
import Data.ByteString.Internal
import Data.IORef
import Data.List
import Data.Maybe
import Data.SortedMap
import Network.HTTP.Internal.Bytes
import public Network.HTTP.Connection
import public Network.HTTP.Parser
import public Network.HTTP.Transport
import public Network.HTTP.Types
import public Network.HTTP2.Config
import Network.HTTP2.Connection
import Network.URI
import System
import System.Concurrency
import System.Crash
import System.File

%default covering

--------------------------------------------------------------------------
-- Requests and responses
--------------------------------------------------------------------------

||| A request, as a handler sees it.
public export
record Request where
  constructor MkRequest
  method : Method
  ||| The request target as it was received.
  target : ByteString
  ||| The path of the target, percent-encoded as it was received (`*` for
  ||| the asterisk form of `OPTIONS`, empty for `CONNECT`).
  path : ByteString
  ||| The query of the target (without the `?`), percent-encoded.
  query : Maybe ByteString
  version : Version
  headers : Headers
  ||| The body: read it with `readChunk` (a piece at a time) or `readAll`
  ||| (`requestBody` reads it up to the limit of the server).
  body : BodyReader
  ||| The most bytes that `requestBody` accepts (`maxBodySize`).
  bodyLimit : Int
  ||| The address of the client, if known.
  remote : Maybe SockAddr
  ||| Did the request come over a secure transport (TLS)?
  secure : Bool

||| The body of a response.
public export
data ResponseBody : Type where
  ||| No bytes (`Content-Length: 0`).
  EmptyBody : ResponseBody
  ||| These bytes.
  BytesBody : ByteString -> ResponseBody
  ||| The output of a builder (built into one byte string first).
  BuilderBody : Builder -> ResponseBody
  ||| Bytes written by a function, a piece at a time (`writeBody`), of a
  ||| length declared in advance (`Content-Length`) or not (in the chunked
  ||| coding; to an HTTP/1.0 client, up to the end of the connection).  The
  ||| function is not run for a response to `HEAD`.  If it writes another
  ||| number of bytes than it declared, or a write fails, the connection is
  ||| closed after it.
  StreamBody : (length : Maybe Int) -> (BodyWriter -> IO ()) -> ResponseBody
  ||| No body: after the head (typically `101 Switching Protocols`, with
  ||| the `Connection` and `Upgrade` fields given by the handler, which the
  ||| server keeps), the function takes the connection over (the bytes that
  ||| came after the request are in it: `readSome` gives them first); the
  ||| server closes it when the function returns.
  UpgradeBody : (Conn -> IO ()) -> ResponseBody

||| A response.
public export
record Response where
  constructor MkResponse
  status : Status
  headers : Headers
  body : ResponseBody

||| A handler of requests.
public export
Handler : Type
Handler = Request -> IO Response

||| A response with a status, fields and body.
export
respond : Status -> Headers -> ResponseBody -> Response
respond = MkResponse

||| A response with an empty body.
export
emptyResponse : Status -> Response
emptyResponse s = MkResponse s emptyHeaders EmptyBody

textPlain : ByteString
textPlain = "text/plain; charset=utf-8"

contentTypeField : ByteString
contentTypeField = "Content-Type"

||| A response with a text body, as `text/plain; charset=utf-8`.
export
textResponse : Status -> String -> Response
textResponse s t = MkResponse s (addHeader contentTypeField textPlain emptyHeaders) (BytesBody (fromString t))

||| A response with a body of bytes and a content type.
export
bytesResponse : Status -> (contentType : ByteString) -> ByteString -> Response
bytesResponse s ct b = MkResponse s (addHeader contentTypeField ct emptyHeaders) (BytesBody b)

||| The response with one more field.
export
withHeader : (name, value : ByteString) -> Response -> Response
withHeader n v r = { headers $= addHeader n v } r

||| A response with the status and its reason phrase as text (`404 Not
||| Found`).
export
statusResponse : Status -> Response
statusResponse s = textResponse s (show s.code ++ " " ++ toStringLossy s.reason ++ "\n")

||| The body of a request, read up to the limit of the server
||| (`BodyTooLarge` beyond it).
export
requestBody : Request -> IO (Either HttpError ByteString)
requestBody r = readAll r.body r.bodyLimit

||| A handler of a function that can fail: a `Left` is answered with 500
||| and the message given to the log function (not to the client).
export
fromEither : (log : String -> IO ()) -> (Request -> IO (Either String Response)) -> Handler
fromEither log h req = do
  Right resp <- h req
    | Left msg => do log ("handler failed: " ++ msg)
                     pure (statusResponse statusInternalServerError)
  pure resp

--------------------------------------------------------------------------
-- Crashes of handlers
--------------------------------------------------------------------------

-- Give a message to the error log; a crash of the log itself is dropped.
safeLog : (String -> IO ()) -> String -> IO ()
safeLog log msg = ignore (catchCrash (log msg))

-- Report a crash of handler code (`what` says which) to the error log.
logCrash : (String -> IO ()) -> String -> CrashInfo -> IO ()
logCrash log what c =
  safeLog log (what ++ " crashed: " ++ show c ++ maybe "" ("\n" ++) c.backtrace)

-- A response whose body is made by the handler as it is written: a
-- builder is built here, inside the boundary of the handler.
strictBody : Response -> Response
strictBody r = case r.body of
  BuilderBody b => { body := BytesBody (toByteString b) } r
  _ => r

-- Run a handler in a crash boundary (with its builder built): `onCrash`
-- if it crashed (and the crash was logged).
runHandler : (String -> IO ()) -> (onCrash : Response) -> Handler -> Request -> IO Response
runHandler log onCrash h req = do
  r <- catchCrash (strictBody <$> h req)
  case r of
    Right resp => pure resp
    Left c => do logCrash log "handler" c; pure onCrash

-- Run the function of a `StreamBody` or an `UpgradeBody` in a crash
-- boundary: False if it crashed (and the crash was logged).
runBodyFunction : (String -> IO ()) -> IO () -> IO Bool
runBodyFunction log act = do
  r <- catchCrash act
  case r of
    Right () => pure True
    Left c => do logCrash log "response body function" c; pure False

--------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------

||| What the access log gets for each response.
public export
record AccessLogEntry where
  constructor MkAccessLogEntry
  remote : Maybe SockAddr
  method : Method
  target : ByteString
  version : Version
  status : Int
  ||| The bytes of the response body that were sent (for `HEAD`, those of
  ||| the body that was not sent).
  bodyBytes : Int
  ||| From the end of the head of the request to the end of the response.
  durationNs : Int

||| The configuration of a server.  Times are in milliseconds; 0 is no
||| limit.
public export
record ServerConfig where
  constructor MkServerConfig
  address : SockAddr
  ||| The length of the queue of connections not accepted yet.
  backlog : Int
  ||| The limits of the head parser.  Its `maxContentLength` is replaced by
  ||| `maxBodySize`.
  limits : Limits
  ||| The whole head of a request must come within this time, counted from
  ||| its first byte (or from the connection for the first request).  A
  ||| client that is slower gets 408 and the connection is closed.
  headTimeout : Int
  ||| Each read of a request body must bring bytes within this time.
  bodyTimeout : Int
  ||| How long a persistent connection may wait for its next request.
  idleTimeout : Int
  ||| Each write of a response must be done within this time.
  writeTimeout : Int
  ||| The most connections at a time: beyond it, the server stops accepting
  ||| until one closes (the system keeps the others in the backlog).
  maxConnections : Int
  ||| The largest request body: a larger `Content-Length` gets 413 before
  ||| the handler runs, a larger chunked body makes the reads of the
  ||| handler fail with `BodyTooLarge`.
  maxBodySize : Int
  ||| How much of a body that the handler did not read is read and dropped
  ||| so that the connection can go on; for more, it is closed.
  maxDrain : Int
  ||| The size of the scratch buffer of each connection.
  bufferSize : Int
  ||| The value of the `Server` field, if there is to be one.
  serverName : Maybe ByteString
  ||| Called after each response.
  accessLog : Maybe (AccessLogEntry -> IO ())
  ||| Where the server reports what went wrong (a handler that failed or
  ||| gave fields that are not valid, an accept that failed).
  errorLog : String -> IO ()
  ||| Makes the transport of an accepted socket, in the thread of the
  ||| connection (a TLS server does its handshake here); `Left` with a
  ||| message to give up the connection (the server then closes the
  ||| socket).
  makeTransport : AsyncSocket -> SockAddr -> IO (Either String Transport)
  ||| HTTP/2: its settings and limits, and whether it is served on plain
  ||| connections whose client starts with the HTTP/2 preface (`h2c` with
  ||| prior knowledge).  A TLS connection for which ALPN selected `h2` is
  ||| always served with HTTP/2.
  http2 : H2Config

||| The transport of a socket as it is (`socketTransport`).
export
plainTransport : AsyncSocket -> SockAddr -> IO (Either String Transport)
plainTransport s a = pure (Right (socketTransport s (Just a)))

stderrLog : String -> IO ()
stderrLog msg = ignore (fPutStrLn stderr msg)

||| A server on an address with: a backlog of 1024, the default limits of
||| the parser, 10 s for a head, 30 s for each read of a body and each write,
||| 60 s of idle keep-alive, 10,000 connections, bodies up to 10 MiB, 64 KiB
||| of drain, a buffer of 4 KiB, no `Server` field, no access log, errors on
||| the standard error, plain sockets, and HTTP/2 as `defaultH2Config` says
||| (with `h2c`).
export
defaultServerConfig : SockAddr -> ServerConfig
defaultServerConfig a =
  MkServerConfig a 1024 defaultLimits 10000 30000 60000 30000 10000 10485760 65536 4096
                 Nothing Nothing stderrLog plainTransport defaultH2Config

--------------------------------------------------------------------------
-- The date
--------------------------------------------------------------------------

dayNames : List String
dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

monthNames : List String
monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

nth : Int -> List String -> String
nth _ [] = "?"
nth 0 (x :: _) = x
nth n (_ :: xs) = nth (n - 1) xs

pad2 : Int -> String
pad2 n = if n < 10 then "0" ++ show n else show n

||| A time in seconds since the epoch in the format of the `Date` field
||| (RFC 9110 section 5.6.7): `Sun, 06 Nov 1994 08:49:37 GMT`.
export
httpDate : (secondsSinceEpoch : Int) -> String
httpDate t =
  let days = t `div` 86400
      sod = t `mod` 86400
      wday = (days + 4) `mod` 7
      z = days + 719468
      era = (if z >= 0 then z else z - 146096) `div` 146097
      doe = z - era * 146097
      yoe = (doe - doe `div` 1460 + doe `div` 36524 - doe `div` 146096) `div` 365
      doy = doe - (365 * yoe + yoe `div` 4 - yoe `div` 100)
      mp = (5 * doy + 2) `div` 153
      d = doy - (153 * mp + 2) `div` 5 + 1
      m = if mp < 10 then mp + 3 else mp - 9
      y = yoe + era * 400 + (if m <= 2 then 1 else 0)
  in nth wday dayNames ++ ", " ++ pad2 d ++ " " ++ nth (m - 1) monthNames ++ " "
     ++ show y ++ " " ++ pad2 (sod `div` 3600) ++ ":" ++ pad2 ((sod `div` 60) `mod` 60)
     ++ ":" ++ pad2 (sod `mod` 60) ++ " GMT"

-- The `Date` field line of the current second, made at most once a second
-- (the second of the monotonic clock, and its line).
record DateCache where
  constructor MkDateCache
  second : Int
  line : ByteString

-- The `Date` field line of the second of a time of the clock of the
-- deadlines (`nowNs`), made at most once a second.
dateLineAt : IORef DateCache -> Int -> IO ByteString
dateLineAt ref t = do
  let s = t `div` 1000000000
  c <- readIORef ref
  if c.second == s then pure c.line else do
    wall <- time
    let l = fromString ("Date: " ++ httpDate (cast wall) ++ "\r\n")
    writeIORef ref (MkDateCache s l)
    pure l

dateLine : IORef DateCache -> IO ByteString
dateLine ref = do
  t <- nowNs
  dateLineAt ref t

--------------------------------------------------------------------------
-- Server state
--------------------------------------------------------------------------

-- A connection that the server knows of: its transport, whether it waits
-- for a request (so that a shutdown can end it at once), and how to drain
-- it if it has its own way (HTTP/2: GOAWAY, then the end with its last
-- stream).
record ConnEntry where
  constructor MkConnEntry
  transport : Transport
  idle : IORef Bool
  drainIt : IORef (Maybe (IO ()))

||| A running server.
export
record Server where
  constructor MkServer
  config : ServerConfig
  handler : Handler
  listener : AsyncSocket
  ||| The address the server listens on (with the port that it got, for
  ||| port 0).
  boundAddress : SockAddr
  stopping : IORef Bool
  -- The connections, under the lock.
  lock : Mutex
  conns : IORef (SortedMap Int ConnEntry)
  count : IORef Int
  nextId : IORef Int
  accepted : IORef Int
  acceptDone : IORef Bool
  date : IORef DateCache
  -- The limits of the head parser with `maxBodySize`, and the parser.
  reqLimits : Limits
  parser : HeadParser RequestHead
  -- signalled (under the lock) when the server has stopped
  stopped : Condition
  stopDone : IORef Bool

||| The address the server listens on (with the port it got if the
||| configuration asked for port 0).
export
serverAddress : Server -> SockAddr
serverAddress s = s.boundAddress

||| The number of connections open now.
export
openConnections : Server -> IO Int
openConnections s = readIORef s.count

||| The number of connections accepted since the start.
export
acceptedConnections : Server -> IO Int
acceptedConnections s = readIORef s.accepted

register : Server -> Transport -> IO (Int, ConnEntry)
register s t = do
  idle <- newIORef False
  dr <- newIORef Nothing
  let e = MkConnEntry t idle dr
  mutexAcquire s.lock
  i <- readIORef s.nextId
  writeIORef s.nextId (i + 1)
  m <- readIORef s.conns
  writeIORef s.conns (insert i e m)
  modifyIORef s.count (+ 1)
  mutexRelease s.lock
  pure (i, e)

unregister : Server -> Int -> IO ()
unregister s i = do
  mutexAcquire s.lock
  m <- readIORef s.conns
  writeIORef s.conns (delete i m)
  modifyIORef s.count (\n => n - 1)
  mutexRelease s.lock

-- Shut down the reading side of the connections that wait for a request
-- (all of them if `all`), so that their threads see the end of the stream.
pokeConnections : Server -> (all : Bool) -> IO ()
pokeConnections s all = do
  mutexAcquire s.lock
  m <- readIORef s.conns
  traverse_ poke (values m)
  mutexRelease s.lock
  where
    poke : ConnEntry -> IO ()
    poke e = do
      dr <- readIORef e.drainIt
      case dr of
        Just act => if all then transportShutdown e.transport ShutBoth else act
        Nothing => do
          idle <- readIORef e.idle
          when (all || idle) $ transportShutdown e.transport (if all then ShutBoth else ShutRead)

--------------------------------------------------------------------------
-- Writing responses
--------------------------------------------------------------------------

crlf : ByteString
crlf = "\r\n"

colonSpace : ByteString
colonSpace = ": "

http11Space : ByteString
http11Space = "HTTP/1.1 "

contentLengthColon : ByteString
contentLengthColon = "Content-Length: "

chunkedLine : ByteString
chunkedLine = "Transfer-Encoding: chunked\r\n"

closeLine : ByteString
closeLine = "Connection: close\r\n"

keepAliveLine : ByteString
keepAliveLine = "Connection: keep-alive\r\n"

serverColon : ByteString
serverColon = "Server: "

continueBytes : ByteString
continueBytes = "HTTP/1.1 100 Continue\r\n\r\n"

closeToken : ByteString
closeToken = "close"

-- How the server frames the body it sends.
data Framing = FLength Int | FChunked | FNone

-- Is the field one that the server writes itself?
isFramingField : Header -> Bool
isFramingField h = eqLower h.name hContentLength || eqLower h.name hTransferEncoding

-- What one pass over the fields of a response finds, packed in an `Int`
-- (so that the pass allocates nothing): the flags below in the low five
-- bits, and above them the bytes of the field lines that the server
-- writes when it drops the framing fields (`name: value` and CRLF each).
-- -1 if a field is not valid (`isValidHeaderName`, `isValidHeaderValue`).
%inline
fDate, fServer, fConnection, fClose, fFraming, fShift : Int
fDate = 1
fServer = 2
fConnection = 4
fClose = 8
fFraming = 16
fShift = 32

%inline
hasFlag : Int -> Int -> Bool
hasFlag info f = prim__and_Int info f /= 0

%inline
infoSize : Int -> Int
infoSize info = prim__shr_Int info 5

-- The flags and size of one valid field.  Only names of the lengths of
-- the fields that the server looks at are compared.
fieldInfo : ByteString -> ByteString -> Int
fieldInfo n v =
  let ln = lengthInt n
      sz = (ln + lengthInt v + 4) * fShift
  in case ln of
       4 => if eqLower n hDate then sz + fDate else sz
       6 => if eqLower n hServer then sz + fServer else sz
       10 => if eqLower n hConnection
                then sz + (if listHasToken closeToken v then fConnection + fClose else fConnection)
                else sz
       14 => if eqLower n hContentLength then fFraming else sz
       17 => if eqLower n hTransferEncoding then fFraming else sz
       _ => sz

-- Check the fields (the last first) and gather what the server needs to
-- know of them (see `fieldInfo`).
scanFields : List Header -> Int -> Int
scanFields [] acc = acc
scanFields (MkHeader n v :: hs) acc =
  if isValidHeaderName n && isValidHeaderValue v
     then let fi = fieldInfo n v in
          -- (the sizes add up, the flags are joined)
          scanFields hs (prim__or_Int (acc + prim__and_Int fi (-32)) (prim__and_Int fi 31))
     else -1

-- The bytes of the field lines of the framing fields.
framingSize : List Header -> Int -> Int
framingSize [] acc = acc
framingSize (h :: hs) acc =
  framingSize hs (if isFramingField h then acc + lengthInt h.name + lengthInt h.value + 4 else acc)

-- Copy the bytes of a byte string to an offset of a buffer.
%inline
copyIn : Buffer -> Int -> ByteString -> IO ()
copyIn dst at (UnsafeBS b o n) = bufCopy b o n dst at

-- Write the field lines so that the last one ends at `end`, from the last
-- field to the first (the order of the list), dropping the framing fields
-- if `drop`.  The writes go backwards, so that the list is not reversed.
putFieldsBack : (drop : Bool) -> Buffer -> (end : Int) -> List Header -> IO ()
putFieldsBack drop b e l = do
  () <- pure ()
  case l of
    [] => pure ()
    (MkHeader n v :: hs) =>
      if drop && (eqLower n hContentLength || eqLower n hTransferEncoding)
         then putFieldsBack drop b e hs
         else do
           () <- bufSetByte b (e - 2) 13
           let s = e - (lengthInt n + lengthInt v + 4)
           copyIn b s n
           bufSetByte b (s + lengthInt n) 58
           bufSetByte b (s + lengthInt n + 1) 32
           copyIn b (s + lengthInt n + 2) v
           bufSetByte b (e - 1) 10
           putFieldsBack drop b s hs

-- The status lines of the usual statuses, written as they are when the
-- status has the reason phrase of `statusFromCode`.
line200, line201, line204, line301, line302, line304, line400, line401, line403, line404,
  line405, line413, line500, line503 : ByteString
line200 = "HTTP/1.1 200 OK\r\n"
line201 = "HTTP/1.1 201 Created\r\n"
line204 = "HTTP/1.1 204 No Content\r\n"
line301 = "HTTP/1.1 301 Moved Permanently\r\n"
line302 = "HTTP/1.1 302 Found\r\n"
line304 = "HTTP/1.1 304 Not Modified\r\n"
line400 = "HTTP/1.1 400 Bad Request\r\n"
line401 = "HTTP/1.1 401 Unauthorized\r\n"
line403 = "HTTP/1.1 403 Forbidden\r\n"
line404 = "HTTP/1.1 404 Not Found\r\n"
line405 = "HTTP/1.1 405 Method Not Allowed\r\n"
line413 = "HTTP/1.1 413 Content Too Large\r\n"
line500 = "HTTP/1.1 500 Internal Server Error\r\n"
line503 = "HTTP/1.1 503 Service Unavailable\r\n"

-- The precomputed status line of a code (empty if there is none).
knownLine : Int -> ByteString
knownLine code = case code of
  200 => line200
  201 => line201
  204 => line204
  301 => line301
  302 => line302
  304 => line304
  400 => line400
  401 => line401
  403 => line403
  404 => line404
  405 => line405
  413 => line413
  500 => line500
  503 => line503
  _ => Data.ByteString.empty

-- The status line of a status: the precomputed one if the reason phrase is
-- the usual one (`HTTP/1.1 ` and the reason are 9 and 2 bytes of it), or
-- empty.
statusLineOf : Status -> ByteString
statusLineOf (MkStatus code reason) =
  let l = knownLine code
      n = lengthInt reason
  in if lengthInt l == n + 14 && unsafeMatchesAt reason l 13 then l else Data.ByteString.empty

-- Write the decimal digits of `m` that end at index `i` (exclusive),
-- backwards.
putDigitsBack : Buffer -> Int -> Int -> IO ()
putDigitsBack b i m = do
  -- (a statement without `()` before an `if` makes the rest a closure)
  () <- bufSetByte b (i - 1) (cast (48 + rem10 m))
  if m < 10 then pure () else putDigitsBack b (i - 1) (quot10 m)

-- Write `n` (not negative) in decimal at `at`; the offset after it.
putDec : Buffer -> Int -> Int -> IO Int
putDec b at n = do
  -- (a `let` before the first action would make the action a closure)
  () <- putDigitsBack b (at + decimalLength n) n
  pure (at + decimalLength n)

-- Copy a byte string to an offset; the offset after it.
%inline
putBS : Buffer -> Int -> ByteString -> IO Int
putBS b at bs = do copyIn b at bs; pure (at + lengthInt bs)

-- (Some of the functions below start with `() <- pure ()`: an `IO`
-- function whose body chooses between actions that are not all `do`
-- blocks is compiled to one that returns a closure, and a bind first
-- makes the choice call them directly.  Likewise a statement that is
-- followed by an `if` or a `case` is written `() <- statement`.)

putServer : Buffer -> Int -> Maybe ByteString -> IO Int
putServer b at m = do
  () <- pure ()
  case m of
    Nothing => pure at
    Just n => do
      at <- putBS b at serverColon
      at <- putBS b at n
      putBS b at crlf

putFraming : Buffer -> Int -> Framing -> IO Int
putFraming b at fr = do
  () <- pure ()
  case fr of
    FLength n => do
      at <- putBS b at contentLengthColon
      at <- putDec b at n
      putBS b at crlf
    FChunked => putBS b at chunkedLine
    FNone => pure at

putMaybe : Buffer -> Int -> Maybe ByteString -> IO Int
putMaybe b at m = do
  () <- pure ()
  case m of
    Nothing => pure at
    Just l => putBS b at l

-- Write the status line; the offset after it.
putStatusLine : Buffer -> Status -> IO Int
putStatusLine b st = do
  () <- pure ()
  let sl = statusLineOf st
  if lengthInt sl > 0 then putBS b 0 sl else do
    at <- putBS b 0 http11Space
    at <- putDecimal b at (st.code `mod` 1000)
    at <- putByte b at 32
    at <- putBS b at st.reason
    putBS b at crlf

-- Write a head into a buffer of the connection: the status line, the
-- fields of the handler (dropping the framing fields unless
-- `keepFraming`), `Date` and `Server` unless the handler gave them, the
-- framing and the `Connection` field.  `info` is what `scanFields` found
-- in the fields, and `now` the time, for the `Date` field.  Then send it
-- with the body (see `sendHeadAndBody`).
sendHead : Server -> Conn -> Status -> Headers -> (info : Int) -> (keepFraming : Bool) -> Framing ->
           (connLine : Maybe ByteString) -> (now : Int) -> (body : ByteString) -> (deadline : Int) ->
           IO (Either HttpError ())
sendHead srv c st hs info keepFraming fr connLine now body dl = do
  let fields = headersToListRev hs
  date <- if hasFlag info fDate then pure Data.ByteString.empty else dateLineAt srv.date now
  let server = if hasFlag info fServer then Nothing else srv.config.serverName
  let fsize = if keepFraming && hasFlag info fFraming
                 then infoSize info + framingSize fields 0 else infoSize info
  let size = fsize + lengthInt st.reason + lengthInt date
             + maybe 0 (\n => lengthInt n + 10) server + 120
  b <- headBuffer c size
  at <- putStatusLine b st
  () <- putFieldsBack (not keepFraming && hasFlag info fFraming) b (at + fsize) fields
  at <- putBS b (at + fsize) date
  at <- putServer b at server
  at <- putFraming b at fr
  at <- putMaybe b at connLine
  at <- putBS b at crlf
  sendHeadAndBody c b at body dl

-- What writing a response gave: whether the connection can go on, and the
-- bytes of the body.
record Written where
  constructor MkWritten
  ok : Bool
  status : Int
  bytes : Int

-- The `Connection` field line for a connection that goes on (`keep`) or
-- not, given the version of the request and what `scanFields` found in the
-- fields of the handler.
connectionLine : Bool -> Version -> (info : Int) -> Maybe ByteString
connectionLine keep v info =
  if keep
     then if v.minor == 0 && not (hasFlag info fConnection) then Just keepAliveLine else Nothing
     else if hasFlag info fClose then Nothing else Just closeLine

sendResult : Either HttpError () -> Bool
sendResult (Right ()) = True
sendResult (Left _) = False

isHead : Method -> Bool
isHead HEAD = True
isHead _ = False

-- A deadline `ms` milliseconds after `now`, or none (-1) for 0 or less.
%inline
deadlineAt : Int -> Int -> Int
deadlineAt now ms = if ms <= 0 then -1 else now + ms * 1000000

-- Write a response to a request, whose fields `scanFields` found valid
-- (`info`).  `keep`: whether the connection should go on after it (it may
-- not, if writing fails or the body asks for the end of the connection).
-- `now` is the time when the handler returned.
writeResponse : Server -> Conn -> Method -> Version -> Response -> (info : Int) -> (keep : Bool) ->
                (now : Int) -> IO Written
writeResponse srv c m v resp@(MkResponse st hs body) info keep0 now = do
  () <- pure ()
  let code = st.code
  let keep = keep0 && not (hasFlag info fClose)
  let dl = deadlineAt now srv.config.writeTimeout
  case body of
    UpgradeBody f => do
      r <- sendHead srv c st hs info True FNone Nothing now Data.ByteString.empty dl
      when (sendResult r) $ ignore (runBodyFunction srv.config.errorLog (f c))
      pure (MkWritten False code 0)
    body =>
      if code < 200 || code == 204 || code == 304
         then do
           r <- sendHead srv c st hs info False FNone (connectionLine keep v info) now Data.ByteString.empty dl
           pure (MkWritten (keep && sendResult r) code 0)
         else case body of
           EmptyBody => strict code keep dl Data.ByteString.empty
           BytesBody bs => strict code keep dl bs
           BuilderBody bld => strict code keep dl (toByteString bld)
           StreamBody len f => stream code keep dl len f
           UpgradeBody _ => pure (MkWritten False code 0)
  where
    strict : Int -> Bool -> Int -> ByteString -> IO Written
    strict code keep dl bs = do
      let n = lengthInt bs
      r <- sendHead srv c resp.status resp.headers info False (FLength n) (connectionLine keep v info) now (if isHead m then Data.ByteString.empty else bs) dl
      pure (MkWritten (keep && sendResult r) code n)

    stream : Int -> Bool -> Int -> Maybe Int -> (BodyWriter -> IO ()) -> IO Written
    stream code keep dl len f = do
      let hs = resp.headers
      let wdl = deadlineAfterMs srv.config.writeTimeout
      case len of
        Just n => do
          Right () <- sendHead srv c resp.status hs info False (FLength n) (connectionLine keep v info) now Data.ByteString.empty dl
            | Left _ => pure (MkWritten False code 0)
          if isHead m then pure (MkWritten keep code n) else do
            w <- rawWriter c (Just n) wdl
            -- (after a crash the body is left short: the connection ends)
            True <- runBodyFunction srv.config.errorLog (f w)
              | False => do k <- bodyBytesWritten w; pure (MkWritten False code k)
            r <- finishBody w
            k <- bodyBytesWritten w
            pure (MkWritten (keep && sendResult r) code k)
        Nothing =>
          if isHead m
             then do
               r <- sendHead srv c resp.status hs info False FNone (connectionLine keep v info) now Data.ByteString.empty dl
               pure (MkWritten (keep && sendResult r) code 0)
          else if v.minor >= 1
             then do
               Right () <- sendHead srv c resp.status hs info False FChunked (connectionLine keep v info) now Data.ByteString.empty dl
                 | Left _ => pure (MkWritten False code 0)
               w <- chunkedWriter c wdl
               -- (after a crash the last chunk is not sent, so that the
               -- client sees that the body is not complete)
               True <- runBodyFunction srv.config.errorLog (f w)
                 | False => do k <- bodyBytesWritten w; pure (MkWritten False code k)
               r <- finishBody w
               k <- bodyBytesWritten w
               pure (MkWritten (keep && sendResult r) code k)
             else do
               -- HTTP/1.0: the body ends with the connection.
               Right () <- sendHead srv c resp.status hs info False FNone (connectionLine False v info) now Data.ByteString.empty dl
                 | Left _ => pure (MkWritten False code 0)
               w <- rawWriter c Nothing wdl
               ignore (runBodyFunction srv.config.errorLog (f w))
               k <- bodyBytesWritten w
               pure (MkWritten False code k)

-- Answer a request that cannot be served (a malformed head, a timeout)
-- and say that the connection ends.
sendError : Server -> Conn -> Status -> IO ()
sendError srv c st = do
  let body = fromString (show st.code ++ " " ++ toStringLossy st.reason ++ "\n")
  let hs = addHeader contentTypeField textPlain emptyHeaders
  now <- nowNs
  ignore (sendHead srv c st hs (max 0 (scanFields (headersToListRev hs) 0)) False (FLength (lengthInt body))
                   (Just closeLine) now body (deadlineAt now srv.config.writeTimeout))

-- Close a connection whose peer may still be sending: end the writing
-- side, then read and drop what comes (for at most 64 KiB and a second),
-- so that the system does not answer the unread bytes with a reset that
-- would lose the response on the way.
lingerClose : Conn -> IO ()
lingerClose c = do
  transportShutdown (connTransport c) ShutWrite
  dl <- deadlineAfterMs 1000
  go dl 0
  where
    go : Int -> Int -> IO ()
    go dl n =
      if n > 65536 then pure () else do
        Right bs <- readSome c dl
          | Left _ => pure ()
        if lengthInt bs == 0 then pure () else go dl (n + lengthInt bs)

--------------------------------------------------------------------------
-- Connections
--------------------------------------------------------------------------

-- The path and query of a request target.
splitTarget : Method -> ByteString -> Maybe (ByteString, Maybe ByteString)
splitTarget m t =
  case parseRequestTarget m t of
    Right (OriginForm p q) => Just (p, q)
    Right (AbsoluteForm u) => Just (if lengthInt u.path == 0 then "/" else u.path, u.query)
    Right (AuthorityForm _ _) => Just (Data.ByteString.empty, Nothing)
    Right AsteriskForm => Just ("*", Nothing)
    Left _ => Nothing

-- Is the body one that the handler may still be reading while it is
-- written?
isStream : ResponseBody -> Bool
isStream (StreamBody _ _) = True
isStream (UpgradeBody _) = True
isStream _ = False

-- Read what the handler left of the request body, so that the next request
-- can be read: True if that worked.  Not if reading failed, nor if the
-- client waits for a `100 Continue` that was not sent (it may never send
-- the body), nor if more than `maxDrain` bytes are left.
finishBodyRead : (expectsContinue : Bool) -> BodyReader -> Int -> IO Bool
finishBodyRead cont body maxDrain = do
  failed <- bodyFailed body
  if failed then pure False else do
    ended <- bodyEnded body
    if ended then pure True else do
      started <- bodyStarted body
      if cont && not started then pure False else drain body maxDrain

-- What to do after a request: go on (with the time when the handler
-- returned, from which the deadline of the next request is counted), or
-- stop.
data Next = Continue Int | Stop | StopLinger

-- The answer to a request whose handler crashed (HTTP/1.1: the connection
-- ends after it).
crashResponse : Response
crashResponse = withHeader "Connection" "close" (statusResponse statusInternalServerError)

-- (HTTP/2: the stream ends, not the connection)
h2CrashResponse : Response
h2CrashResponse = statusResponse statusInternalServerError

-- Write an entry of the access log (a crash of the log is reported to the
-- error log).
accessLogEntry : ServerConfig -> IO () -> IO ()
accessLogEntry cfg act = do
  Left c <- catchCrash act
    | Right () => pure ()
  logCrash cfg.errorLog "access log" c

-- Serve one request whose head was read.
-- Serve one request whose head and target were read and checked.
serveTarget : Server -> Conn -> RequestHead -> BodyFraming -> (path : ByteString) ->
              (query : Maybe ByteString) -> IO Next
serveTarget srv c h framing path query = do
        () <- pure ()
        let cfg = srv.config
        let cont = h.version.minor >= 1 && hasBody framing && expectsContinue h
        let wdl = cfg.writeTimeout
        body <- if hasBody framing
                   then bodyReader c framing cfg.maxBodySize (deadlineAfterMs cfg.bodyTimeout)
                          (if cont then Just (do d <- deadlineAfterMs wdl
                                                 sendBytes c continueBytes d)
                                   else Nothing)
                   else pure noBody
        let t = connTransport c
        start <- case cfg.accessLog of
                   Nothing => pure 0
                   Just _ => nowNs
        -- (a crash of the handler is answered with 500, and the connection
        -- ends after it)
        resp <- runHandler cfg.errorLog crashResponse srv.handler
                    (MkRequest h.method h.target path query h.version h.headers
                               body cfg.maxBodySize (transportPeer t) (transportSecure t))
        now <- nowNs
        -- The rest of the body, so that the next request can be read.
        -- The rest of the body must be read before the next request: here
        -- for a response that does not read it, after the response for one
        -- that may (a stream).
        let persistent = isPersistent h.version h.headers
        let streams = isStream resp.body
        keep0 <- if not persistent then pure False
                 else if streams then pure True
                 else finishBodyRead cont body cfg.maxDrain
        -- (a stream may read the body after the head of the response is
        -- out, too late for a `100 Continue`)
        if streams && cont then ignore (startBody body) else pure ()
        stop <- readIORef srv.stopping
        let info = scanFields (headersToListRev resp.headers) 0
        w <- if info >= 0
                then writeResponse srv c h.method h.version resp info (keep0 && not stop) now
                else do
                  cfg.errorLog ("response field not valid: " ++ maybe "" (\bad => show bad.name) (invalidHeader resp.headers))
                  let err = statusResponse statusInternalServerError
                  writeResponse srv c h.method h.version err (scanFields (headersToListRev err.headers) 0)
                                (keep0 && not stop) now
        case cfg.accessLog of
          Nothing => pure ()
          Just log => do
            end <- nowNs
            accessLogEntry cfg (log (MkAccessLogEntry (transportPeer t) h.method h.target h.version w.status w.bytes (end - start)))
        keep <- if w.ok && streams then finishBodyRead cont body cfg.maxDrain else pure w.ok
        if keep then pure (Continue now) else do
          ended <- bodyEnded body
          pure (if ended then Stop else StopLinger)
  where
    hasBody : BodyFraming -> Bool
    hasBody NoBody = False
    hasBody (ContentLength 0) = False
    hasBody _ = True

-- Serve one request whose head was read.  A target in the origin form (the
-- usual `/path?query`) is split without `parseRequestTarget`.
serveRequest : Server -> Conn -> RequestHead -> IO Next
serveRequest srv c h = do
  () <- pure ()
  case requestFraming srv.reqLimits h of
    Left e => do sendError srv c (statusFromCode (errorStatus e)); pure StopLinger
    Right framing =>
      let t = h.target
          q = if isConnect h.method then -2 else originFormQuery t
      in if q == -1 then serveTarget srv c h framing t Nothing
         else if q >= 0 then serveTarget srv c h framing (takeInt q t) (Just (dropInt (q + 1) t))
         else case splitTarget h.method t of
                Nothing => do sendError srv c statusBadRequest; pure StopLinger
                Just (path, query) => serveTarget srv c h framing path query
  where
    isConnect : Method -> Bool
    isConnect CONNECT = True
    isConnect _ = False

-- The loop of a connection: read a head, serve it, again.  `now` is the
-- time from which the deadline of the head is counted.
connectionLoop : Server -> Conn -> IORef Bool -> (first : Bool) -> (now : Int) -> IO ()
connectionLoop srv c idle first now = do
  let cfg = srv.config
  stop <- readIORef srv.stopping
  if stop && not first then pure () else do
    writeIORef idle True
    r <- readHead c srv.parser (deadlineAt now (if first then cfg.headTimeout else cfg.idleTimeout)) cfg.headTimeout
    () <- writeIORef idle False
    case r of
      Right h => do
        next <- serveRequest srv c h
        case next of
          Continue t => connectionLoop srv c idle False t
          Stop => pure ()
          StopLinger => lingerClose c
      Left (BadHead e) => do sendError srv c (statusFromCode (errorStatus e)); lingerClose c
      Left TimedOut => do sendError srv c statusRequestTimeout; lingerClose c
      Left _ => pure ()

--------------------------------------------------------------------------
-- HTTP/2
--------------------------------------------------------------------------

||| `HTTP/2`, the version of the requests that come over HTTP/2.
export
http2 : Version
http2 = MkVersion 2 0

h2Field : ByteString -> ByteString -> HeaderField
h2Field n v = MkHeaderField n v False

h2Status, h2ContentLength, h2Date, h2Server : ByteString
h2Status = ":status"
h2ContentLength = "content-length"
h2Date = "date"
h2Server = "server"

-- The `:status` field of a code.
statusField : Int -> HeaderField
statusField 200 = h2Field h2Status "200"
statusField code = h2Field h2Status (decimalBytes (code `mod` 1000))

-- The value of a `Date` line ("Date: ...\r\n").
dateValue : ByteString -> ByteString
dateValue l = sliceFromTo 6 (lengthInt l - 2) l

-- Write a response on a stream: the status and the bytes of the body.
h2Respond : Server -> H2Conn -> H2Stream -> Method -> Response -> IO (Int, Int)
h2Respond srv c s m resp = do
  let st = resp.status
  let code = st.code
  date <- if hasHeader hDate resp.headers then pure [] else do
            l <- dateLine srv.date
            pure [MkHeaderField h2Date (dateValue l) False]
  let server = case srv.config.serverName of
                 Just n => if hasHeader hServer resp.headers then [] else [MkHeaderField h2Server n False]
                 Nothing => []
  let base = statusField code
             :: filter (\f => f.name /= hContentLength) (toFields resp.headers) ++ date ++ server
  let clField = \n => [MkHeaderField h2ContentLength (decimalBytes n) False]
  let noBody = code < 200 || code == 204 || code == 304
  case resp.body of
    UpgradeBody _ => do
      srv.config.errorLog "a response that takes the connection over (UpgradeBody) is not possible over HTTP/2"
      ignore (sendHeaders c s [h2Field h2Status "500", h2Field h2ContentLength "0"] True)
      pure (500, 0)
    body =>
      if noBody then do ignore (sendHeaders c s base True); pure (code, 0) else
        case body of
          StreamBody len f =>
            if m == HEAD then do ignore (sendHeaders c s (base ++ maybe [] clField len) True); pure (code, fromMaybe 0 len) else do
              Right () <- sendHeaders c s (base ++ maybe [] clField len) False
                | Left _ => pure (code, 0)
              w <- dataWriter c s len
              -- (after a crash the stream is not ended: streamDone resets
              -- it with INTERNAL_ERROR)
              ok <- runBodyFunction srv.config.errorLog (f w)
              when ok $ ignore (finishBody w)
              n <- bodyBytesWritten w
              pure (code, n)
          _ => do
            let bs = case body of
                       BytesBody b => b
                       BuilderBody b => toByteString b
                       _ => Data.ByteString.empty
            let n = lengthInt bs
            if n == 0 || m == HEAD
               then do ignore (sendHeaders c s (base ++ clField n) True); pure (code, n)
               else do
                 Right () <- sendHeaders c s (base ++ clField n) False
                   | Left _ => pure (code, 0)
                 ignore (sendData c s bs True)
                 pure (code, n)

-- Serve the request of a stream, in its thread.
h2Serve : Server -> Transport -> H2Conn -> H2Stream -> H2Request -> IO ()
h2Serve srv t c s rh = do
  let cfg = srv.config
  let m = methodFromBytes rh.method
  let target = fromMaybe (fromMaybe Data.ByteString.empty rh.authority) rh.path
  start <- case cfg.accessLog of
             Nothing => pure 0
             Just _ => nowNs
  (code, n) <-
    if maybe False (> cfg.maxBodySize) rh.contentLength
       then h2Respond srv c s m (statusResponse statusContentTooLarge)
       else case splitTarget m target of
         Nothing => h2Respond srv c s m (statusResponse statusBadRequest)
         Just (path, query) => do
           body <- streamBody c s
           let hs = case rh.authority of
                      Just a => if hasHeader hHost rh.fields then rh.fields else addHeader "host" a rh.fields
                      Nothing => rh.fields
           -- (a crash of the handler is answered with 500)
           resp <- runHandler cfg.errorLog h2CrashResponse srv.handler
                       (MkRequest m target path query http2 hs body cfg.maxBodySize
                                  (transportPeer t) (transportSecure t))
           resp <- case invalidHeader resp.headers of
                     Nothing => pure resp
                     Just bad => do
                       cfg.errorLog ("response field not valid: " ++ show bad.name)
                       pure (statusResponse statusInternalServerError)
           h2Respond srv c s m resp
  streamDone c s
  case cfg.accessLog of
    Nothing => pure ()
    Just log => do
      end <- nowNs
      accessLogEntry cfg (log (MkAccessLogEntry (transportPeer t) m target http2 code n (end - start)))

-- A request whose header list is too large: 431.
h2TooLarge : H2Conn -> H2Stream -> IO ()
h2TooLarge c s = do
  ignore (sendHeaders c s [h2Field h2Status "431", h2Field h2ContentLength "0"] True)
  streamDone c s

-- Serve a connection with HTTP/2.
serveH2 : Server -> Conn -> ConnEntry -> IO ()
serveH2 srv c e = do
  let cfg = srv.config
  let t = connTransport c
  runServer (MkServerSide cfg.http2 cfg.writeTimeout cfg.bodyTimeout cfg.idleTimeout cfg.headTimeout
                          cfg.errorLog
                          (\drain => do writeIORef e.drainIt (Just drain)
                                        stop <- readIORef srv.stopping
                                        when stop drain)
                          (\h2c, st, rh => do
                              -- (the handler has a boundary of its own:
                              -- this one is for the rest)
                              Left info <- catchCrash (h2Serve srv t h2c st rh)
                                | Right () => pure ()
                              logCrash cfg.errorLog ("stream " ++ show (streamId st)) info)
                          h2TooLarge)
            c

-- Does the client start with the preface of HTTP/2?  What was read stays
-- in the connection.
sniffPreface : Conn -> Int -> ByteString -> IO Bool
sniffPreface c dl acc = case checkPreface acc of
  PrefaceOk _ => do unread c acc; pure True
  PrefaceBad => do unread c acc; pure False
  PrefaceNeedMore _ => do
    Right bs <- readSome c dl
      | Left _ => do unread c acc; pure False
    if lengthInt bs == 0 then do unread c acc; pure False
      else sniffPreface c dl (if lengthInt acc == 0 then bs else acc <+> bs)

||| What the server runs for each connection, in a thread of its own: make
||| the transport, serve the requests (with HTTP/2 if ALPN selected `h2`,
||| or if the client starts with the preface of HTTP/2 and `cleartext` of
||| the `http2` configuration allows it), close.  The handlers run in crash
||| boundaries of their own; another one around the connection makes sure
||| that a crash anywhere else (in the error or access log, say) closes the
||| connection and leaves the server running.
export
connectionEntry : Server -> AsyncSocket -> SockAddr -> IO ()
connectionEntry srv s addr = do
  Right t <- srv.config.makeTransport s addr
    | Left msg => do safeLog srv.config.errorLog ("connection from " ++ show addr ++ ": " ++ msg)
                     ignore (close s)
  (i, e) <- register srv t
  r <- catchCrash $ do
    c <- newConn t srv.config.bufferSize
    if transportProtocol t == Just h2Protocol then serveH2 srv c e else do
      h2 <- if srv.config.http2.cleartext && not (transportSecure t)
               then do dl <- deadlineAfterMs srv.config.headTimeout
                       sniffPreface c dl Data.ByteString.empty
               else pure False
      if h2 then serveH2 srv c e else do
        now <- nowNs
        connectionLoop srv c e.idle True now
  case r of
    Right () => pure ()
    Left c => logCrash srv.config.errorLog ("connection from " ++ show addr) c
  unregister srv i
  transportClose t

--------------------------------------------------------------------------
-- Accepting
--------------------------------------------------------------------------

acceptLoop : Server -> IO ()
acceptLoop srv = do
  stop <- readIORef srv.stopping
  if stop then finish else do
    n <- readIORef srv.count
    if n >= srv.config.maxConnections
       then do usleep 2000; acceptLoop srv
       else do
         d <- deadlineAfterMs 1000
         r <- acceptFrom srv.listener (Just d)
         case r of
           Right (s, addr) => do
             ignore (setOption s NoDelay 1)
             modifyIORef srv.accepted (+ 1)
             _ <- fork (connectionEntry srv s addr)
             acceptLoop srv
           Left Timeout => acceptLoop srv
           Left e => do
             stop <- readIORef srv.stopping
             if stop then finish else do
               srv.config.errorLog ("accept: " ++ show e)
               -- (out of descriptors, say: give the connections time to end)
               usleep 10000
               acceptLoop srv
  where
    finish : IO ()
    finish = do
      ignore (close srv.listener)
      writeIORef srv.acceptDone True

||| Start a server: listen on the address of the configuration and accept
||| connections in a thread of their own.  Returns when the server listens.
export
startServer : ServerConfig -> Handler -> IO (Either NetError Server)
startServer cfg h = do
  Right l <- listenOn cfg.address cfg.backlog
    | Left e => pure (Left e)
  addr <- either (const cfg.address) id <$> localAddress l
  srv <- [| MkServer (pure cfg) (pure h) (pure l) (pure addr) (newIORef False)
                     makeMutex (newIORef empty) (newIORef 0) (newIORef 0) (newIORef 0)
                     (newIORef False) (newIORef (MkDateCache (-1) Data.ByteString.empty))
                     (pure ({ maxContentLength := Just cfg.maxBodySize } cfg.limits))
                     (pure (requestParser cfg.limits))
                     makeCondition (newIORef False) |]
  _ <- fork (acceptLoop srv)
  pure (Right srv)

waitUntil : Int -> IO Bool -> IO Bool
waitUntil deadline cond = do
  True <- cond
    | False => do
        t <- now
        if t >= deadline then pure False else do
          usleep 5000
          waitUntil deadline cond
  pure True

||| Stop a server gracefully: stop accepting, close the connections that
||| wait for a request, let the requests in progress finish (their
||| connections close after the response) for up to `graceMs`
||| milliseconds, then shut down the connections that are left and wait
||| (for at most a second more) for their threads.  Returns when it is done;
||| `waitServer` returns then too.  Calling it again does nothing.
export
stopServer : Server -> (graceMs : Int) -> IO ()
stopServer srv grace = do
  already <- readIORef srv.stopping
  if already then pure () else do
    writeIORef srv.stopping True
    -- wake up the accept loop (shutdown(2) of a listening socket makes
    -- accept fail on Linux; elsewhere the loop sees the flag within a
    -- second)
    ignore (shutdown srv.listener ShutRead)
    start <- now
    let graceEnd = start + max 0 grace * 1000000
    pokeConnections srv False
    done <- waitUntil graceEnd (do pokeConnections srv False
                                   n <- readIORef srv.count
                                   pure (n == 0))
    when (not done) $ do
      pokeConnections srv True
      t <- now
      ignore (waitUntil (t + 1000000000) ((== 0) <$> readIORef srv.count))
    t <- now
    ignore (waitUntil (t + 2000000000) (readIORef srv.acceptDone))
    mutexAcquire srv.lock
    writeIORef srv.stopDone True
    conditionBroadcast srv.stopped
    mutexRelease srv.lock

||| Wait until the server has been stopped (by `stopServer` in another
||| thread).  Any number of threads may wait.
export
waitServer : Server -> IO ()
waitServer srv = do
  mutexAcquire srv.lock
  waitDone
  mutexRelease srv.lock
  where
    waitDone : IO ()
    waitDone = do
      done <- readIORef srv.stopDone
      if done then pure () else do
        conditionWait srv.stopped srv.lock
        waitDone

||| Run a server until it is stopped (by a handler, or another thread, with
||| `stopServer`): `startServer` then `waitServer`.
export
serve : ServerConfig -> Handler -> IO (Either NetError ())
serve cfg h = do
  Right srv <- startServer cfg h
    | Left e => pure (Left e)
  waitServer srv
  pure (Right ())
