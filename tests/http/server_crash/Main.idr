-- Crashes of handlers (System.Crash): a route that crashes (a missing case
-- on some input, an access out of a Buffer, a stream body that crashes
-- after its first bytes) gets 500, or a response cut short, the error log
-- gets the message and the access log the entry, and the server goes on:
-- over HTTP/1.1 the connection closes and the next request on a new one
-- succeeds; over HTTP/2 the other streams of the connection complete; a
-- WebSocket session that crashes is closed with 1011; 1,000 crashing
-- requests in a row leave the server answering.
import Data.Buffer
import Data.ByteString
import Data.IORef
import Data.List
import Data.Maybe
import Data.String
import HttpTest
import Network.HTTP.Client
import Network.HTTP.Router
import Network.WebSocket
import System
import System.Concurrency
import System.Crash

%default covering

-- (covers only "a" and "b")
partial
pick : String -> String
pick "a" = "first"
pick "b" = "second"

routes : List Route
routes =
  [ route GET "/hello" (\_, _ => pure (textResponse statusOK "hello\n"))
  , route GET "/pick/:x" (\_, ps => pure (textResponse statusOK (assert_total (pick (fromMaybe "" (param "x" ps))) ++ "\n")))
  , route GET "/buffer" (\_, _ => do
      Just b <- newBuffer 8
        | Nothing => pure (statusResponse statusInternalServerError)
      n <- getBits32 b 100
      pure (textResponse statusOK (show n)))
  , route GET "/stream" (\_, _ => pure (respond statusOK emptyHeaders (StreamBody Nothing (\w => do
      ignore (writeBody w "partial")
      ignore (writeBody w (fromString (assert_total (pick "c"))))))))
  , route GET "/slow" (\_, _ => do usleep 200000; pure (textResponse statusOK "slow\n"))
  , websocketRoute "/ws" defaultAcceptOptions (\_, _, ws => do
      Right m <- receive ws
        | Left _ => pure ()
      ignore (sendText ws (assert_total (pick "z"))))
  ]

-- (the line of a message, without the place of the function in the source)
firstLine : String -> String
firstLine s = case lines s of
  (l :: _) => l
  [] => ""

showReply : String -> Either HttpError Reply -> IO ()
showReply label (Left e) = putStrLn "\{label}: error"
showReply label (Right r) = putStrLn "\{label}: \{show r.status.code} \{show r.body}"

-- Print what the logs got since the last time.
flushLogs : IORef (List String) -> IORef (List String) -> IO ()
flushLogs errs acc = do
  usleep 50000
  es <- readIORef errs
  writeIORef errs []
  traverse_ (\e => putStrLn ("  error log: " ++ firstLine e)) (reverse es)
  as <- readIORef acc
  writeIORef acc []
  traverse_ (\a => putStrLn ("  access log: " ++ a)) (reverse as)

logTo : Mutex -> IORef (List String) -> String -> IO ()
logTo lock r msg = do mutexAcquire lock; modifyIORef r (msg ::); mutexRelease lock

main : IO ()
main = do
  errs <- newIORef []
  acc <- newIORef []
  lock <- makeMutex
  let cfg = { errorLog := logTo lock errs,
              accessLog := Just (\e => logTo lock acc "\{toStringLossy e.target} \{show e.status}") }
            (defaultServerConfig (Inet "127.0.0.1" 0))
  srv <- orDie "start" (startServer cfg (router routes))
  let addr = serverAddress srv
  let base = "http://\{show addr}"
  -- HTTP/1.1: a crash, then a request on the same connection, which is
  -- not served (the connection ends after the 500)
  exchange addr "a missing case, and a request after it on the same connection"
    "GET /pick/c HTTP/1.1\r\nHost: x\r\n\r\nGET /hello HTTP/1.1\r\nHost: x\r\n\r\n" False 3000
  flushLogs errs acc
  exchange addr "a buffer read out of range" "GET /buffer HTTP/1.1\r\nHost: x\r\n\r\n" False 3000
  flushLogs errs acc
  exchange addr "a stream body that crashes: the last chunk is not sent"
    "GET /stream HTTP/1.1\r\nHost: x\r\n\r\n" False 3000
  flushLogs errs acc
  c <- newClient defaultClientConfig
  showReply "a route that does not crash" !(httpGet c (base ++ "/pick/a"))
  showReply "then one that does" !(httpGet c (base ++ "/pick/c"))
  showReply "then on a new connection" !(httpGet c (base ++ "/hello"))
  putStrLn "connections opened: \{show !(connectionsOpened c)}"
  flushLogs errs acc
  -- 1,000 crashing requests in a row
  writeIORef errs []
  rs <- for [the Int 1 .. 1000] (\_ => httpGet c (base ++ "/pick/d"))
  putStrLn "1,000 crashing requests, answered with 500: \{show (length (filter (either (const False) (\r => r.status.code == 500)) rs))}"
  putStrLn "errors logged: \{show (length !(readIORef errs))}"
  writeIORef errs []
  writeIORef acc []
  showReply "and then" !(httpGet c (base ++ "/hello"))
  closeIdle c
  -- HTTP/2: the other streams of the connection go on
  c2 <- newClient ({ http2PriorKnowledge := True } defaultClientConfig)
  done <- makeChannel
  traverse_ (\i => fork (do
      r <- httpGet c2 (base ++ "/slow")
      channelPut done (either (const False) (\x => x.status.code == 200) r))) [the Int 1 .. 10]
  usleep 50000
  showReply "HTTP/2, a crash while 10 streams wait" !(httpGet c2 (base ++ "/pick/e"))
  oks <- traverse (\_ => channelGet done) [the Int 1 .. 10]
  putStrLn "the 10 other streams: \{show (length (filter id oks))} answered with 200"
  showReply "HTTP/2, a stream body that crashes" !(httpGet c2 (base ++ "/stream"))
  showReply "HTTP/2, then" !(httpGet c2 (base ++ "/hello"))
  putStrLn "connections opened: \{show !(connectionsOpened c2)}"
  usleep 50000
  es <- readIORef errs
  putStrLn "errors logged: \{show (sort (map firstLine es))}"
  writeIORef errs []
  writeIORef acc []
  closeIdle c2
  -- WebSocket: the session crashes, the connection is closed with 1011
  Right ws <- connectWebSocket defaultConnectOptions ("ws://\{show addr}/ws")
    | Left e => putStrLn "connect: \{show e}"
  ignore (sendText ws "hi")
  Left info <- receive ws
    | Right _ => putStrLn "a message?"
  putStrLn "WebSocket session crashed: closed with \{show info.code} \{show (toStringLossy info.reason)}"
  usleep 100000
  es <- readIORef errs
  traverse_ (\e => putStrLn ("  error log: " ++ firstLine e)) (reverse es)
  putStrLn "crashes caught: \{show !crashesCaught}"
  stopServer srv 1000
