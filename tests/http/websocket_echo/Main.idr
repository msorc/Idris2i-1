-- The WebSocket client and server of the http library against each other,
-- through the router: echo of messages of many sizes (as one frame and in
-- fragments), subprotocols, concurrent senders on one connection, the
-- closing handshake started by each side, a close while another thread is
-- blocked in `receive`, and a connection that is dropped without a close.
import Data.Bits
import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal
import Data.IORef
import Data.List
import Data.List1
import Data.String
import HttpTest
import Network.HTTP.Client
import Network.HTTP.Router
import Network.WebSocket
import System
import System.Concurrency

%default covering

-- What the server sessions report, printed by the main thread in order.
Events : Type
Events = Channel String

echo : WebSocket -> IO CloseInfo
echo ws = do
  Right m <- receive ws
    | Left i => pure i
  ignore (sendMessage ws m)
  echo ws

echoSession : Events -> Request -> Params -> WebSocket -> IO ()
echoSession ev _ _ ws = do
  i <- echo ws
  channelPut ev ("server: echo session \{show i}")

protoSession : Events -> Request -> Params -> WebSocket -> IO ()
protoSession ev _ _ ws = do
  ignore (sendText ws ("subprotocol " ++ maybe "none" toStringLossy (subprotocol ws)))
  i <- echo ws
  pure ()

closingSession : Events -> Request -> Params -> WebSocket -> IO ()
closingSession ev _ _ ws = do
  ignore (sendText ws "bye")
  i <- closeWebSocket ws 4000 "server done"
  channelPut ev ("server: \{show i}")

silentSession : Events -> Request -> Params -> WebSocket -> IO ()
silentSession ev _ _ ws = do
  r <- receive ws
  channelPut ev ("server: silent session " ++ either show show r)

abortSession : Events -> Request -> Params -> WebSocket -> IO ()
abortSession ev _ _ ws = do
  usleep 50000
  abort ws

routes : Events -> List Route
routes ev =
  [ websocketRoute "/echo" ({ config.maxMessageSize := 8000000 } defaultAcceptOptions) (echoSession ev)
  , websocketRoute "/proto" ({ subprotocols := ["chat.v1", "chat.v2"] } defaultAcceptOptions) (protoSession ev)
  , websocketRoute "/proto-x" ({ subprotocols := ["x"] } defaultAcceptOptions) (protoSession ev)
  , websocketRoute "/closing" defaultAcceptOptions (closingSession ev)
  , websocketRoute "/silent" defaultAcceptOptions (silentSession ev)
  , websocketRoute "/abort" defaultAcceptOptions (abortSession ev)
  , route GET "/" (\_, _ => pure (textResponse statusOK "a page\n"))
  ]

-- A payload of `n` bytes: ASCII text, or bytes 0..255 for binary.
payload : Bool -> Int -> ByteString
payload text n = unsafeCreate n (\b => fill b 0)
  where
    fill : Buffer -> Int -> IO ()
    fill b i = if i >= n then pure () else do
      setBits8 b i (if text then cast (97 + i `mod` 26) else cast (i `mod` 251))
      fill b (i + 1)

-- Text with code points of 1 to 4 bytes, of about `n` bytes.
utf8Text : Int -> String
utf8Text n = concat (replicate (cast (n `div` 10)) "aé€😀")

clientOpts : ConnectOptions
clientOpts = { config.maxMessageSize := 8000000 } defaultConnectOptions

openWS : String -> String -> IO WebSocket
openWS base path = do
  Right ws <- connectWebSocket clientOpts (base ++ path)
    | Left e => do putStrLn "connect \{path}: \{show e}"; exitFailure
  pure ws

roundTrip : WebSocket -> Message -> IO String
roundTrip ws m = do
  Right () <- sendMessage ws m
    | Left e => pure "send failed: \{show e}"
  Right m' <- receive ws
    | Left i => pure "receive: \{show i}"
  pure (if m == m' then "ok" else "different: \{show m'}")

sizes : List Int
sizes = [0, 1, 125, 126, 65535, 65536, 3 * 1024 * 1024]

-- The message of thread `t`, number `i`: its length varies, and its bytes
-- say who sent it.
threadMessage : Int -> Int -> ByteString
threadMessage t i =
  let n = 4 + ((t * 7919 + i * 104729) `mod` 5000)
      tag = fromString (show t ++ ":" ++ show i ++ ":")
  in tag <+> unsafeCreate (n - lengthInt tag) (\b => fill b 0 (n - lengthInt tag) (cast (65 + t)))
  where
    fill : Buffer -> Int -> Int -> Bits8 -> IO ()
    fill b j n c = if j >= n then pure () else do setBits8 b j c; fill b (j + 1) n c

-- Is a message one of `threadMessage` (whole)?
wholeMessage : ByteString -> Bool
wholeMessage bs =
  case map toStringLossy (forget (Data.ByteString.split 58 bs)) of
    [t, i, _] => case (parseInteger {a = Int} t, parseInteger {a = Int} i) of
                        (Just t', Just i') => threadMessage t' i' == bs
                        _ => False
    _ => False

concurrentSenders : String -> IO ()
concurrentSenders base = do
  ws <- openWS base "/echo"
  let threads = 8
  let perThread = 200
  done <- makeChannel
  for_ [0 .. threads - 1] $ \t => fork $ do
    for_ [0 .. perThread - 1] $ \i => ignore (sendBinary ws (threadMessage t i))
    channelPut done ()
  (good, bad) <- count ws (threads * perThread) 0 0
  for_ [1 .. threads] $ \_ => channelGet done
  putStrLn "concurrent senders: \{show good} whole messages, \{show bad} broken"
  ignore (closeWebSocket ws 1000 "")
  where
    count : WebSocket -> Int -> Int -> Int -> IO (Int, Int)
    count ws left good bad =
      if left <= 0 then pure (good, bad) else do
        Right m <- receive ws
          | Left i => pure (good, bad)
        if wholeMessage (messageBytes m) then count ws (left - 1) (good + 1) bad
                                         else count ws (left - 1) good (bad + 1)

main : IO ()
main = do
  ev <- makeUnboundedChannel
  Right srv <- startServer (defaultServerConfig (Inet "127.0.0.1" 0)) (router (routes ev))
    | Left e => putStrLn (show e)
  let base = "ws://\{show (serverAddress srv)}"

  -- echo, one frame per message
  ws <- openWS base "/echo"
  for_ sizes $ \n => do
    r1 <- roundTrip ws (BinaryMessage (payload False n))
    r2 <- roundTrip ws (TextMessage (payload True n))
    putStrLn "echo \{show n}: binary \{r1}, text \{r2}"
  r <- roundTrip ws (TextMessage (fromString (utf8Text 1000)))
  putStrLn "echo UTF-8 text: \{r}"
  r <- the (IO String) $ do
    Right () <- sendText ws "as a String"
      | Left e => pure (show e)
    Right m <- receive ws
      | Left i => pure (show i)
    pure (messageString m)
  putStrLn "echo String: \{r}"
  Right () <- ping ws "hello"
    | Left e => putStrLn "ping: \{show e}"
  r <- roundTrip ws (TextMessage "after the ping")
  n <- pongCount ws
  putStrLn "after a ping: \{r}, pongs \{show n}"
  r <- sendTextBytes ws (pack [0xC3, 0x28])
  putStrLn "sendTextBytes of bad UTF-8: \{show r}"
  r <- ping ws (payload True 126)
  putStrLn "ping of 126 bytes: \{show r}"
  i <- closeWebSocket ws 1000 "done"
  putStrLn "client: \{show i}"
  putStrLn !(channelGet ev)
  r <- sendText ws "after the close"
  putStrLn "send after the close: \{show r}"
  r <- receive ws
  putStrLn "receive after the close: \{either show show r}"

  -- echo, in fragments of 1000 bytes
  Right wf <- connectWebSocket ({ config.fragmentSize := 1000 } clientOpts) (base ++ "/echo")
    | Left e => putStrLn "connect: \{show e}"
  for_ [999, 1000, 1001, 65536, 3 * 1024 * 1024] $ \n => do
    r1 <- roundTrip wf (BinaryMessage (payload False n))
    r2 <- roundTrip wf (TextMessage (payload True n))
    putStrLn "fragmented echo \{show n}: binary \{r1}, text \{r2}"
  r <- roundTrip wf (TextMessage (fromString (utf8Text 20000)))
  putStrLn "fragmented UTF-8 text (split inside code points): \{r}"
  i <- closeWebSocket wf 1001 "going"
  putStrLn "client: \{show i}"
  putStrLn !(channelGet ev)

  -- subprotocols
  for_ [("/proto", ["chat.v2", "chat.v1"]), ("/proto", ["other"]), ("/proto-x", ["chat.v1"]), ("/proto", [])] $ \(path, offer) => do
    Right wp <- connectWebSocket ({ subprotocols := offer } clientOpts) (base ++ path)
      | Left e => putStrLn "connect: \{show e}"
    Right m <- receive wp
      | Left i => putStrLn (show i)
    putStrLn "\{path} offering \{show offer}: client sees \{show (subprotocol wp)}, server says \{messageString m}"
    ignore (closeWebSocket wp 1000 "")

  -- concurrent senders on one connection
  concurrentSenders base
  putStrLn !(channelGet ev)

  -- the server closes
  wc <- openWS base "/closing"
  r <- receive wc
  putStrLn "client got: \{either show messageString r}"
  r <- receive wc
  putStrLn "client got: \{either show messageString r}"
  putStrLn !(channelGet ev)

  -- a close from another thread while a receive is blocked
  wsil <- openWS base "/silent"
  got <- makeChannel
  _ <- fork $ do
    r <- receive wsil
    channelPut got ("blocked receive returned: " ++ either show show r)
  usleep 200000
  i <- closeWebSocket wsil 1000 "from another thread"
  putStrLn "client: \{show i}"
  putStrLn !(channelGet got)
  putStrLn !(channelGet ev)

  -- dropped without a close, by the client
  wd <- openWS base "/silent"
  abort wd
  putStrLn !(channelGet ev)
  -- and by the server
  wa <- openWS base "/abort"
  r <- receive wa
  putStrLn "client after the server dropped it: \{either show show r}"

  -- the router: the page, and a plain GET of a WebSocket path
  c <- newClient defaultClientConfig
  let http = "http://\{show (serverAddress srv)}"
  Right p <- httpGet c (http ++ "/")
    | Left e => putStrLn (show e)
  putStrLn "GET /: \{show p.status.code} \{show p.body}"
  Right p <- httpGet c (http ++ "/echo")
    | Left e => putStrLn (show e)
  putStrLn "GET /echo without upgrade: \{show p.status.code} upgrade=\{show (lookupHeader "upgrade" p.headers)}"
  Left e <- connectWebSocket clientOpts (base ++ "/nowhere")
    | Right _ => putStrLn "connected to /nowhere"
  putStrLn "connect to /nowhere: \{show e}"
  Left e <- connectWebSocket clientOpts ("wss://\{show (serverAddress srv)}/echo")
    | Right _ => putStrLn "connected with wss"
  putStrLn "wss without TLS: \{show e}"
  Left e <- connectWebSocket clientOpts ("http://\{show (serverAddress srv)}/echo")
    | Right _ => putStrLn "connected with http"
  putStrLn "http URL: \{show e}"

  stopServer srv 1000
  putStrLn "stopped"
