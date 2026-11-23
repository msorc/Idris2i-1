-- A few HTTPS requests of each kind through the server and the client, and
-- a failed handshake, run under Valgrind by the test script (when it is
-- installed): no memory errors and no leaks in the TLS transport.
import Data.ByteString
import HttpsTest
import Network.HTTP.Client
import Network.HTTP.Router
import Network.HTTP.Server
import Network.HTTP.TLS
import Network.TLS
import System

%default covering

routes : List Route
routes =
  [ route GET "/hello" $ \_, _ => pure (textResponse statusOK "hello\n")
  , route POST "/echo" $ \req, _ => do
      Right b <- requestBody req
        | Left e => pure (statusResponse statusBadRequest)
      pure (bytesResponse statusOK "application/octet-stream" b)
  , route GET "/stream" $ \_, _ =>
      pure (respond statusOK emptyHeaders (StreamBody Nothing (\w => do
              ignore (writeBody w "one ")
              ignore (writeBody w (Data.ByteString.replicate 10000 120))
              ignore (writeBody w " two\n"))))
  ]

main : IO ()
main = do
  [_, certs] <- getArgs
    | _ => die "usage: main CERTS"
  sctx <- serverContext certs "server" []
  (cfg, stats) <- httpsServerConfig sctx ({ errorLog := \_ => pure () } (defaultServerConfig (Inet "127.0.0.1" 0)))
  Right srv <- startServer cfg (router routes)
    | Left e => die "start: \{show e}"
  let base = "https://localhost:\{show (addrPort (serverAddress srv))}"
  c <- httpsClient !(clientContext certs [])
  Right r <- httpGet c (base ++ "/hello")
    | Left e => putStrLn (show e)
  putStrLn "GET: \{show r.status.code} \{show r.body}"
  Right r <- httpPost c (base ++ "/echo") "text/plain" (Data.ByteString.replicate 20000 121)
    | Left e => putStrLn (show e)
  putStrLn "POST: \{show r.status.code} \{show (length r.body)} bytes"
  Right r <- fetch c POST (base ++ "/echo") emptyHeaders (RequestStream Nothing (\w => do
               ignore (writeBody w "abc")
               ignore (writeBody w "def")))
    | Left e => putStrLn (show e)
  putStrLn "POST chunked: \{show r.status.code} \{show r.body}"
  Right r <- httpGet c (base ++ "/stream")
    | Left e => putStrLn (show e)
  putStrLn "GET stream: \{show r.status.code} \{show (length r.body)} bytes"
  -- a client that does not trust the server
  Right sys <- defaultHTTPSClientConfig
    | Left e => die "default client: \{show e}"
  csys <- newClient sys
  r <- httpGet csys (base ++ "/hello")
  putStrLn "untrusted: \{either show (const "no error") r}"
  closeIdle c
  stopServer srv 1000
  n <- handshakeCounts stats
  putStrLn "handshakes: \{show n.succeeded} succeeded, \{show n.failed} failed"
