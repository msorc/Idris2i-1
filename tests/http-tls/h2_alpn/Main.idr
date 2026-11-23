-- HTTP/2 over TLS, selected with ALPN: the client of the library against
-- the server (both offering h2 and http/1.1), a client that offers only
-- http/1.1 on the same port, an HTTP/2 client on a server that offers
-- only http/1.1, many requests at once on one connection, and a server
-- for curl (it writes its port to `port` and serves until `/quit`).
import Data.ByteString
import Data.IORef
import Data.List
import HttpsTest
import Network.HTTP.Client
import Network.HTTP.Router
import Network.HTTP.Server
import Network.HTTP.TLS
import Network.TLS
import System
import System.Concurrency
import System.File

%default covering

routes : IORef (Maybe Server) -> List Route
routes ref =
  [ route GET "/hello" $ \req, _ => pure (textResponse statusOK "hello over HTTP/\{show req.version.major}.\{show req.version.minor}, secure \{show req.secure}\n")
  , route POST "/echo" $ \req, _ => do
      Right b <- requestBody req
        | Left e => pure (textResponse statusBadRequest (show e))
      pure (textResponse statusOK ("got \{show (length b)} bytes\n"))
  , route GET "/big" $ \_, _ => pure (bytesResponse statusOK "application/octet-stream" (bigBody 1000000))
  , route GET "/quit" $ \_, _ => do
      Just srv <- readIORef ref
        | Nothing => pure (statusResponse statusServiceUnavailable)
      _ <- fork (stopServer srv 1000)
      pure (textResponse statusOK "bye\n")
  ]

result : String -> Either HttpError Reply -> IO ()
result label (Left e) = putStrLn "\{label}: error \{show e}"
result label (Right r) = putStrLn "\{label}: \{show r.status.code} \{show r.body}"

main : IO ()
main = do
  [_, certs, mode] <- getArgs
    | _ => die "usage: main CERTS (client|curl)"
  ref <- newIORef Nothing
  sctx <- serverContext certs "server" ["h2", "http/1.1"]
  (cfg, _) <- httpsServerConfig sctx (defaultServerConfig (Inet "127.0.0.1" 0))
  Right srv <- startServer cfg (router (routes ref))
    | Left e => die "start: \{show e}"
  writeIORef ref (Just srv)
  let base = "https://localhost:\{show (addrPort (serverAddress srv))}"
  if mode == "curl"
    then do
      Right () <- writeFile "port" (show (addrPort (serverAddress srv)))
        | Left e => putStrLn (show e)
      _ <- fork (do sleep 60; stopServer srv 1000)
      waitServer srv
    else do
      c <- httpsClient !(clientContext certs ["h2", "http/1.1"])
      result "h2 client" !(httpGet c (base ++ "/hello"))
      result "POST" !(httpPost c (base ++ "/echo") "text/plain" (Data.ByteString.replicate 100000 65))
      Right r <- httpGet c (base ++ "/big")
        | Left e => putStrLn (show e)
      putStrLn "1 MB: \{checksum r.body}, the same: \{show (r.body == bigBody 1000000)}"
      done <- makeChannel
      traverse_ (\i => fork (do
          r <- httpGet c (base ++ "/big")
          channelPut done (either (const False) (\x => x.body == bigBody 1000000) r))) [the Int 1 .. 50]
      oks <- traverse (\_ => channelGet done) [the Int 1 .. 50]
      putStrLn "50 at once: \{show (length (filter id oks))} right"
      putStrLn "connections: \{show !(connectionsOpened c)}"
      closeIdle c
      c1 <- httpsClient !(clientContext certs ["http/1.1"])
      result "http/1.1 client" !(httpGet c1 (base ++ "/hello"))
      closeIdle c1
      c0 <- httpsClient !(clientContext certs [])
      result "client without ALPN" !(httpGet c0 (base ++ "/hello"))
      closeIdle c0
      sctx1 <- serverContext certs "server" ["http/1.1"]
      (cfg1, _) <- httpsServerConfig sctx1 (defaultServerConfig (Inet "127.0.0.1" 0))
      Right srv1 <- startServer cfg1 (router (routes ref))
        | Left e => die "start: \{show e}"
      c2 <- httpsClient !(clientContext certs ["h2", "http/1.1"])
      result "h2 client, http/1.1 server" !(httpGet c2 "https://localhost:\{show (addrPort (serverAddress srv1))}/hello")
      closeIdle c2
      stopServer srv1 1000
      stopServer srv 1000
