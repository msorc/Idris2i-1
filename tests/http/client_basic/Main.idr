-- The client: redirects (and their limit), reuse of pooled connections
-- (counted by the server), the idle timeout of the pool, a connection that
-- the server closed while it was in the pool, timeouts, a response above
-- the limit, URLs it cannot fetch, and responses of a raw server (until
-- the end of the connection, interim responses, trailers).
import Data.ByteString
import Data.IORef
import Data.List
import Data.String
import HttpTest
import Network.HTTP.Client
import Network.HTTP.Router
import System
import System.Concurrency

%default covering

echo : RouteHandler
echo req _ = do
  Right b <- requestBody req
    | Left e => pure (statusResponse statusBadRequest)
  pure (textResponse statusOK ("\{show req.method} \{toStringLossy b}"))

redirectTo : Status -> String -> Response
redirectTo st loc = withHeader "Location" (fromString loc) (emptyResponse st)

routes : List Route
routes =
  [ route GET "/r/:n" $ \req, ps =>
      let n = the Int (maybe 0 cast (param "n" ps)) in
      pure (if n > 0 then redirectTo statusFound ("/r/" ++ show (n - 1))
                     else textResponse statusOK "end")
  , route POST "/see-other" $ \_, _ => pure (redirectTo statusSeeOther "/echo")
  , route POST "/temporary" $ \_, _ => pure (redirectTo statusTemporaryRedirect "/echo")
  , route GET "/relative/a/b" $ \_, _ => pure (redirectTo statusMovedPermanently "../c")
  , route GET "/relative/c" $ \_, _ => pure (textResponse statusOK "relative ok")
  , route GET "/echo" echo
  , route POST "/echo" echo
  , route GET "/big" $ \_, _ => pure (textResponse statusOK (pack (replicate 5000 'b')))
  , route GET "/slow" $ \_, _ => do usleep 1000000; pure (textResponse statusOK "slow")
  , route GET "/hello" $ \_, _ => pure (textResponse statusOK "hello")
  ]

result : String -> Either HttpError Reply -> IO ()
result label (Left e) = putStrLn "\{label}: error \{show e}"
result label (Right r) = putStrLn "\{label}: \{show r.status.code} \{show r.body}"

-- A server that answers one connection with fixed bytes after the head of
-- the request, then closes it.
rawServer : String -> IO SockAddr
rawServer answer = do
  l <- orDie "listen" (listenOn (Inet "127.0.0.1" 0) 16)
  a <- orDie "address" (localAddress l)
  _ <- fork $ do
    s <- orDie "accept" (accept l Nothing)
    _ <- readUntil s "\r\n\r\n" 2000
    sendRaw s (fromString answer)
    ignore (close s)
    ignore (close l)
  pure a

main : IO ()
main = do
  let scfg = { idleTimeout := 300 } (defaultServerConfig (Inet "127.0.0.1" 0))
  srv <- orDie "start" (startServer scfg (router routes))
  let base = "http://\{show (serverAddress srv)}"
  c <- newClient defaultClientConfig
  -- redirects
  result "three redirects" !(httpGet c (base ++ "/r/3"))
  Right r <- httpGet c (base ++ "/r/2")
    | Left e => putStrLn (show e)
  putStrLn "final URL ends with /r/0: \{show (isSuffixOf "/r/0" r.url)}"
  result "eleven redirects" !(httpGet c (base ++ "/r/11"))
  result "303 after POST" !(httpPost c (base ++ "/see-other") "text/plain" "data")
  result "307 after POST" !(httpPost c (base ++ "/temporary") "text/plain" "data")
  result "relative location" !(httpGet c (base ++ "/relative/a/b"))
  c0 <- newClient ({ maxRedirects := 0 } defaultClientConfig)
  Right r <- httpGet c0 (base ++ "/r/1")
    | Left e => putStrLn (show e)
  putStrLn "not followed: \{show r.status.code} location=\{show (lookupHeader "location" r.headers)}"
  closeIdle c0
  -- reuse
  traverse_ (\_ => ignore (httpGet c (base ++ "/hello"))) [1 .. 20]
  n <- acceptedConnections srv
  putStrLn "server accepted (one connection for c, one for c0): \{show n}"
  -- the server closes the pooled connection after its idle timeout
  usleep 600000
  result "after the server closed the pooled connection" !(httpGet c (base ++ "/hello"))
  result "POST after that" !(httpPost c (base ++ "/echo") "text/plain" "x")
  n <- acceptedConnections srv
  putStrLn "server accepted: \{show n}"
  -- the idle timeout of the pool
  cshort <- newClient ({ idleTimeout := 100 } defaultClientConfig)
  ignore (httpGet cshort (base ++ "/hello"))
  usleep 250000
  ignore (httpGet cshort (base ++ "/hello"))
  o <- connectionsOpened cshort
  putStrLn "connections of a client with a short idle timeout: \{show o}"
  closeIdle cshort
  -- several threads sharing a client
  done <- makeChannel
  traverse_ (\i => fork (do
                rs <- traverse (\_ => httpGet c (base ++ "/hello")) [1 .. 5]
                channelPut done (all (either (const False) (\x => x.status.code == 200)) rs)))
            [1 .. 10]
  oks <- traverse (\_ => channelGet done) [1 .. 10]
  putStrLn "10 threads, 5 requests each: \{show (all id oks)}"
  -- limits and timeouts
  csmall <- newClient ({ maxResponseSize := 1000, requestTimeout := 300 } defaultClientConfig)
  result "response above the limit" !(httpGet csmall (base ++ "/big"))
  result "request timeout" !(httpGet csmall (base ++ "/slow"))
  closeIdle csmall
  -- connect timeout: a listener whose queue is full
  full <- orDie "listen" (listenOn (Inet "127.0.0.1" 0) 0)
  fa <- orDie "address" (localAddress full)
  held <- fillQueue fa [] 0
  cconn <- newClient ({ connectTimeout := 200 } defaultClientConfig)
  result "connect timeout" !(httpGet cconn "http://\{show fa}/")
  traverse_ close held
  ignore (close full)
  -- connection refused
  gone <- orDie "listen" (listenOn (Inet "127.0.0.1" 0) 1)
  ga <- orDie "address" (localAddress gone)
  ignore (close gone)
  result "connection refused" !(httpGet c "http://\{show ga}/")
  -- URLs
  result "https" !(httpGet c "https://example.com/")
  result "ftp" !(httpGet c "ftp://example.com/")
  result "not a URL" !(httpGet c "not a url")
  -- raw servers
  a <- rawServer "HTTP/1.1 200 OK\r\nX-A: 1\r\n\r\nthe body runs until the end"
  result "until the end of the connection" !(httpGet c "http://\{show a}/")
  a <- rawServer "HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 103 Early Hints\r\nLink: </x>\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nfinal"
  result "interim responses" !(httpGet c "http://\{show a}/")
  a <- rawServer "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n2\r\nde\r\n0\r\nX-Trailer: t\r\n\r\n"
  Right (body, trailers) <- withResponse c GET "http://\{show a}/" emptyHeaders NoRequestBody (\resp => do
                               b <- readAll resp.body 1000
                               t <- bodyTrailers resp.body
                               pure (b, t))
    | Left e => putStrLn (show e)
  putStrLn "chunked with trailers: \{show body} \{show trailers}"
  a <- rawServer "HTTP/1.1 200 OK\r\nContent-Length: 3\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n"
  result "Content-Length and Transfer-Encoding" !(httpGet c "http://\{show a}/")
  a <- rawServer "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nshort"
  result "body shorter than its length" !(httpGet c "http://\{show a}/")
  closeIdle c
  stopServer srv 1000
  where
    fillQueue : SockAddr -> List AsyncSocket -> Nat -> IO (List AsyncSocket)
    fillQueue a held n =
      if n >= 64 then pure held else do
        d <- deadlineIn 100000000
        Right s <- connect a (Just d)
          | Left _ => pure held
        fillQueue a (s :: held) (S n)
