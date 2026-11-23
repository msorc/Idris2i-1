-- The server and the client of the http library against each other, and
-- the server against raw requests: every framing of bodies both ways,
-- HEAD, 204, 100-continue, persistent connections and pipelining,
-- `Connection: close`, HTTP/1.0, a handler that fails and one that gives a
-- field that is not valid.
import Data.ByteString
import Data.IORef
import Data.List
import Data.String
import HttpTest
import Network.HTTP.Client
import Network.HTTP.Server
import System

%default covering

-- Copy the request body to the response as it comes.
echoStream : BodyReader -> BodyWriter -> IO ()
echoStream r w = do
  Right (Just bs) <- readChunk r
    | _ => pure ()
  ignore (writeBody w bs)
  echoStream r w

echoBody : Handler
echoBody req = do
  Right b <- requestBody req
    | Left e => pure (textResponse statusBadRequest (show e))
  pure (bytesResponse statusOK "application/octet-stream" b)

routes : List (ByteString, Handler)
routes =
  [ ("/hello", \_ => pure (textResponse statusOK "hello\n"))
  , ("/echo", echoBody)
  , ("/echo-stream", \req => pure (respond statusOK emptyHeaders (StreamBody Nothing (echoStream req.body))))
  , ("/stream", \_ => pure (respond statusOK emptyHeaders (StreamBody Nothing (\w => do
        ignore (writeBody w "one,")
        ignore (writeBody w "two,")
        ignore (writeBody w "three\n")))))
  , ("/stream-len", \_ => pure (respond statusOK emptyHeaders (StreamBody (Just 7) (\w => do
        ignore (writeBody w "abc")
        ignore (writeBody w "defg")))))
  , ("/stream-short", \_ => pure (respond statusOK emptyHeaders (StreamBody (Just 10) (\w => ignore (writeBody w "abc")))))
  , ("/builder", \_ => pure (respond statusOK emptyHeaders (BuilderBody (fromString "built " <+> fromString "body\n"))))
  , ("/empty", \_ => pure (emptyResponse statusOK))
  , ("/nocontent", \_ => pure (textResponse statusNoContent "ignored"))
  , ("/fail", fromEither (\msg => putStrLn "log: \{msg}") (\_ => pure (Left "boom")))
  , ("/badheader", \_ => pure (withHeader "X-Bad" "a\r\nX-Injected: yes" (textResponse statusOK "no\n")))
  , ("/close", \_ => pure (withHeader "Connection" "close" (textResponse statusOK "bye\n")))
  , ("/query", \req => pure (textResponse statusOK (show req.query ++ "\n")))
  ]

app : IORef Int -> Handler
app counter req = do
  modifyIORef counter (+ 1)
  case lookup req.path routes of
    Just h => h req
    Nothing => pure (statusResponse statusNotFound)

showReply : String -> Either HttpError Reply -> IO ()
showReply label (Left e) = putStrLn "\{label}: error \{show e}"
showReply label (Right r) =
  putStrLn "\{label}: \{show r.status.code} cl=\{show (lookupHeader "content-length" r.headers)} te=\{show (lookupHeader "transfer-encoding" r.headers)} body=\{show r.body}"

clientTests : Server -> IO ()
clientTests srv = do
  let base = "http://\{show (serverAddress srv)}"
  c <- newClient defaultClientConfig
  showReply "GET /hello" !(httpGet c (base ++ "/hello"))
  showReply "POST /echo bytes" !(httpPost c (base ++ "/echo") "text/plain" "some bytes")
  showReply "POST /echo empty" !(httpPost c (base ++ "/echo") "text/plain" "")
  showReply "POST /echo chunked" !(fetch c POST (base ++ "/echo") emptyHeaders
                                     (RequestStream Nothing (\w => do ignore (writeBody w "chunk1,")
                                                                      ignore (writeBody w "chunk2"))))
  showReply "POST /echo length" !(fetch c POST (base ++ "/echo") emptyHeaders
                                    (RequestStream (Just 6) (\w => do ignore (writeBody w "len")
                                                                      ignore (writeBody w "gth"))))
  showReply "POST /echo-stream" !(fetch c POST (base ++ "/echo-stream") emptyHeaders
                                    (RequestStream Nothing (\w => traverse_ (\i => writeBody w (fromString (show i ++ ";"))) [1 .. 20])))
  showReply "GET /stream" !(httpGet c (base ++ "/stream"))
  showReply "GET /stream-len" !(httpGet c (base ++ "/stream-len"))
  showReply "GET /builder" !(httpGet c (base ++ "/builder"))
  showReply "HEAD /hello" !(fetch c HEAD (base ++ "/hello") emptyHeaders NoRequestBody)
  showReply "HEAD /stream" !(fetch c HEAD (base ++ "/stream") emptyHeaders NoRequestBody)
  showReply "HEAD /stream-len" !(fetch c HEAD (base ++ "/stream-len") emptyHeaders NoRequestBody)
  showReply "GET /empty" !(httpGet c (base ++ "/empty"))
  showReply "GET /nocontent" !(httpGet c (base ++ "/nocontent"))
  showReply "GET /fail" !(httpGet c (base ++ "/fail"))
  showReply "GET /badheader" !(httpGet c (base ++ "/badheader"))
  showReply "GET /query" !(httpGet c (base ++ "/query?a=1&b=%20"))
  showReply "GET /missing" !(httpGet c (base ++ "/missing"))
  opened <- connectionsOpened c
  putStrLn "client connections opened: \{show opened}"
  showReply "GET /close" !(httpGet c (base ++ "/close"))
  showReply "GET /hello after close" !(httpGet c (base ++ "/hello"))
  opened <- connectionsOpened c
  putStrLn "client connections opened: \{show opened}"
  showReply "GET /stream-short" !(httpGet c (base ++ "/stream-short"))
  closeIdle c

rawTests : Server -> IO ()
rawTests srv = do
  let a = serverAddress srv
  exchange a "pipelined, then the end of the stream"
    ("GET /hello HTTP/1.1\r\nHost: x\r\n\r\n" ++
     "GET /stream HTTP/1.1\r\nHost: x\r\n\r\n" ++
     "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\n\r\nabc" ++
     "POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nhi\r\n0\r\n\r\n" ++
     "HEAD /hello HTTP/1.1\r\nHost: x\r\n\r\n") True 3000
  exchange a "Connection: close"
    "GET /hello HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\nGET /hello HTTP/1.1\r\nHost: x\r\n\r\n" False 3000
  exchange a "HTTP/1.0" "GET /hello HTTP/1.0\r\n\r\n" False 3000
  exchange a "HTTP/1.0 keep-alive"
    "GET /hello HTTP/1.0\r\nConnection: keep-alive\r\n\r\nGET /hello HTTP/1.0\r\n\r\n" False 3000
  exchange a "HTTP/1.0 stream" "GET /stream HTTP/1.0\r\n\r\n" False 3000
  exchange a "unread body is drained"
    "POST /hello HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\n12345GET /hello HTTP/1.1\r\nHost: x\r\n\r\n" True 3000
  -- 100-continue: the server asks for the body when the handler reads it
  s <- orDie "connect" (connect a Nothing)
  sendRaw s "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nExpect: 100-continue\r\n\r\n"
  first <- readUntil s "\r\n\r\n" 3000
  putStrLn "--- 100-continue, interim response"
  putStr (showResponse first)
  sendRaw s "hello"
  ignore (shutdown s ShutWrite)
  (rest, ended) <- readUntilEnd s 3000
  putStrLn "--- 100-continue, final response"
  putStr (showResponse rest)
  ignore (close s)
  -- a handler that does not read the body: no 100, and the connection ends
  exchange a "100-continue, body not read"
    "POST /hello HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nExpect: 100-continue\r\n\r\n" False 3000

main : IO ()
main = do
  counter <- newIORef 0
  let cfg = { errorLog := \msg => putStrLn "server error: \{msg}" } (defaultServerConfig (Inet "127.0.0.1" 0))
  srv <- orDie "start" (startServer cfg (app counter))
  clientTests srv
  rawTests srv
  stopServer srv 2000
  n <- readIORef counter
  putStrLn "handler calls: \{show n}"
