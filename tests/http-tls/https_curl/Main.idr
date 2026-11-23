-- An HTTPS server for curl: it writes its port to the file `port` and
-- serves until it gets `/quit` (or for 60 seconds), then writes what its
-- handshakes came to in the file `handshakes`.
import Data.ByteString
import Data.IORef
import HttpsTest
import Network.HTTP.Router
import Network.HTTP.Server
import Network.HTTP.TLS
import Network.TLS
import System
import System.File

%default covering

routes : Server -> List Route
routes srv =
  [ route GET "/hello" $ \req, _ => pure (textResponse statusOK "hello over TLS: \{show req.secure}\n")
  , route GET "/second" $ \_, _ => pure (textResponse statusOK "second\n")
  , route POST "/echo" $ \req, _ => do
      Right b <- requestBody req
        | Left e => pure (textResponse statusBadRequest (show e ++ "\n"))
      pure (textResponse statusOK ("got \{show (length b)} bytes: \{toStringLossy (Data.ByteString.take 40 b)}\n"))
  , route GET "/quit" $ \_, _ => do
      _ <- fork (stopServer srv 1000)
      pure (textResponse statusOK "bye\n")
  ]

main : IO ()
main = do
  [_, certs] <- getArgs
    | _ => die "usage: main CERTS"
  ctx <- serverContext certs "server" ["http/1.1"]
  (cfg, stats) <- httpsServerConfig ctx (defaultServerConfig (Inet "127.0.0.1" 0))
  ref <- newIORef Nothing
  Right srv <- startServer cfg (\req => do
                 Just s <- readIORef ref
                   | Nothing => pure (statusResponse statusServiceUnavailable)
                 router (routes s) req)
    | Left e => putStrLn (show e)
  writeIORef ref (Just srv)
  Right () <- writeFile "port" (show (addrPort (serverAddress srv)))
    | Left e => putStrLn (show e)
  _ <- fork (do sleep 60; stopServer srv 1000)
  waitServer srv
  n <- handshakeCounts stats
  -- (how many fail depends on curl: when it rejects the certificate, the
  -- handshake may have ended on the side of the server)
  ignore (writeFile "handshakes" "handshakes: \{show (n.succeeded >= 6)} that at least 6 succeeded, \{show (n.failed >= 1)} that at least one failed\n")
