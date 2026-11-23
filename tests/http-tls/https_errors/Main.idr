-- What goes wrong with HTTPS, and how it shows: certificates that the
-- client does not accept (its errors), a plain HTTP request sent to the
-- HTTPS port and a TLS handshake sent to a plain port (both end without
-- hanging, and the servers go on), clients that never finish the handshake
-- (dropped at the deadline, logged and counted).
import Data.ByteString
import Data.IORef
import Data.List
import Data.String
import HttpTest
import HttpsTest
import Network.HTTP.Client
import Network.HTTP.Server
import Network.HTTP.TLS
import Network.Socket.Async
import Network.TLS
import System
import System.Clock

%default covering

hello : Handler
hello _ = pure (textResponse statusOK "hello")

result : String -> Either HttpError Reply -> IO ()
result label (Left e) = putStrLn "\{label}: error \{show e}"
result label (Right r) = putStrLn "\{label}: \{show r.status.code} \{show r.body}"

-- An HTTPS server with these credentials, logging into a list (atomically:
-- the threads of two connections may log at the same time).
httpsServer : String -> String -> IORef (List String) -> IO (Server, HandshakeStats)
httpsServer certs name logs = do
  ctx <- serverContext certs name []
  let base = { headTimeout := 400, errorLog := \m => atomicModifyIORef_ logs (m ::) }
               (defaultServerConfig (Inet "127.0.0.1" 0))
  (cfg, stats) <- httpsServerConfig ctx base
  Right srv <- startServer cfg hello
    | Left e => die "start: \{show e}"
  pure (srv, stats)

-- The message of a log line without the address of the client.
withoutAddress : String -> String
withoutAddress m = case break (== ':') (unpack m) of
  (_, ':' :: rest) => case break (== ':') rest of
    (_, ':' :: rest') => "connection from ADDRESS:" ++ pack rest'
    _ => m
  _ => m

-- Milliseconds since a time of the clock.
msSince : Clock Monotonic -> IO Integer
msSince t0 = do
  t <- clockTime Monotonic
  pure (toNano (timeDifference t t0) `div` 1000000)

main : IO ()
main = do
  [_, certs] <- getArgs
    | _ => die "usage: main CERTS"
  logs <- newIORef []
  c <- httpsClient !(clientContext certs [])
  -- certificates that the client does not accept
  for_ (the (List (String, String)) [("rogue", "signed by an authority that is not trusted"),
        ("other", "for another name"),
        ("expired", "expired")]) $ \(name, what) => do
    (srv, _) <- httpsServer certs name logs
    result "certificate \{what}" !(httpGet c "https://localhost:\{show (addrPort (serverAddress srv))}/")
    stopServer srv 1000
  (srv, stats) <- httpsServer certs "server" logs
  let port = addrPort (serverAddress srv)
  let url = "https://localhost:\{show port}/"
  Right sys <- defaultHTTPSClientConfig
    | Left e => die "default client: \{show e}"
  csys <- newClient sys
  result "the authorities of the system" !(httpGet csys url)
  result "the test authority" !(httpGet c url)
  -- a plain HTTP request to the HTTPS port
  -- (the server closes the connection at once, or resets it: it does not
  -- wait for the deadline of the handshake)
  t0 <- clockTime Monotonic
  s <- orDie "connect" (connect (Inet "127.0.0.1" port) Nothing)
  sendRaw s "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n"
  (bs, ended) <- readUntilEnd s 5000
  ignore (close s)
  ms <- msSince t0
  putStrLn "plain HTTP to the HTTPS port: ended within 300 ms \{show (ms < 300)}, an HTTP response \{show (isPrefixOf "HTTP/" bs)}"
  -- (closed, or reset: the server does not read what the client sent)
  r <- httpGet c "http://localhost:\{show port}/"
  putStrLn "http:// URL to the HTTPS port fails: \{show (either (const True) (const False) r)}"
  -- a TLS handshake to a plain HTTP server
  Right plain <- startServer (defaultServerConfig (Inet "127.0.0.1" 0)) hello
    | Left e => die "start: \{show e}"
  let pport = addrPort (serverAddress plain)
  r <- httpGet c "https://localhost:\{show pport}/"
  putStrLn "https:// URL to a plain port fails: \{show (either (const True) (const False) r)}"
  result "the plain server goes on" !(httpGet c "http://localhost:\{show pport}/")
  stopServer plain 1000
  -- a client that says nothing, and one that stops in the middle of its
  -- ClientHello: dropped at the deadline of the handshake (400 ms)
  t0 <- clockTime Monotonic
  silent <- orDie "connect" (connect (Inet "127.0.0.1" port) Nothing)
  stalled <- orDie "connect" (connect (Inet "127.0.0.1" port) Nothing)
  sendRaw stalled "\x16\x03\x01\x02\x00\x01\x00\x01\x7c\x03\x03"
  (_, e1) <- readUntilEnd silent 5000
  (_, e2) <- readUntilEnd stalled 5000
  ms <- msSince t0
  putStrLn "silent client dropped: \{show e1}, stalled handshake dropped: \{show e2}, within 0.3 to 3 s: \{show (ms >= 300 && ms < 3000)}"
  ignore (close silent)
  ignore (close stalled)
  result "the server goes on" !(httpGet c url)
  -- (the socket of a failed handshake is closed before the failure is
  -- counted and logged, by the thread of the connection)
  usleep 500000
  closeIdle c
  closeIdle csys
  stopServer srv 1000
  n <- handshakeCounts stats
  putStrLn "handshakes: \{show n.succeeded} succeeded, \{show n.failed} failed, \{show n.timedOut} timed out"
  putStrLn "error log:"
  ls <- readIORef logs
  traverse_ (\m => putStrLn ("  " ++ m)) (sort (map withoutAddress ls))
