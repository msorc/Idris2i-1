-- A few requests of each kind through the server and the client, run under
-- Valgrind by the test script (when it is installed): no memory errors
-- and no leaks in the buffers, slices and connections of the library.
import Data.ByteString
import HttpTest
import Network.HTTP.Client
import Network.HTTP.Router
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
  srv <- orDie "start" (startServer (defaultServerConfig (Inet "127.0.0.1" 0)) (router routes))
  let a = serverAddress srv
  let base = "http://\{show a}"
  c <- newClient defaultClientConfig
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
  exchange a "pipelined"
    "GET /hello HTTP/1.1\r\nHost: x\r\n\r\nGET /missing HTTP/1.1\r\nHost: x\r\n\r\n" True 5000
  exchange a "malformed" "GET /hello HTTP/1.1\r\nHost : x\r\n\r\n" True 5000
  closeIdle c
  stopServer srv 1000
