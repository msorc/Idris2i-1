-- A few HTTP/2 requests of each kind through the server and the client,
-- streams reset and a connection error, run under Valgrind by the test
-- script (when it is installed): no memory errors and no leaks.
import Data.ByteString
import H2Raw
import HttpTest
import Network.HTTP.Client
import Network.HTTP.Router
import Network.HTTP2.Frame
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
              ignore (writeBody w (Data.ByteString.replicate 100000 120))
              ignore (writeBody w " two\n"))))
  ]

main : IO ()
main = do
  srv <- orDie "start" (startServer ({ errorLog := \_ => pure () } (defaultServerConfig (Inet "127.0.0.1" 0))) (router routes))
  let a = serverAddress srv
  let base = "http://\{show a}"
  c <- newClient ({ http2PriorKnowledge := True } defaultClientConfig)
  Right r <- httpGet c (base ++ "/hello")
    | Left e => putStrLn (show e)
  putStrLn "GET: \{show r.status.code} \{show r.body}"
  Right r <- httpPost c (base ++ "/echo") "text/plain" (Data.ByteString.replicate 300000 121)
    | Left e => putStrLn (show e)
  putStrLn "POST: \{show r.status.code} \{show (length r.body)} bytes"
  Right r <- fetch c POST (base ++ "/echo") emptyHeaders (RequestStream Nothing (\w => do
               ignore (writeBody w "abc")
               ignore (writeBody w "def")))
    | Left e => putStrLn (show e)
  putStrLn "POST streamed: \{show r.status.code} \{show r.body}"
  Right r <- httpGet c (base ++ "/stream")
    | Left e => putStrLn (show e)
  putStrLn "GET stream: \{show r.status.code} \{show (length r.body)} bytes"
  -- a response not read to its end: the stream is reset
  Right () <- withResponse c GET (base ++ "/stream") emptyHeaders NoRequestBody (\_ => pure ())
    | Left e => putStrLn (show e)
  closeIdle c
  -- raw frames: a malformed request, a connection error
  r <- openRaw a []
  b1 <- block r (get "/hello" ++ [("X-Upper", "1")])
  send r [Headers 1 True True Nothing Nothing b1, DataFrame 0 True Nothing "x"]
  expect r "raw frames" 3000 goaway
  close r
  stopServer srv 1000
