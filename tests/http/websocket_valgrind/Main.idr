-- A small WebSocket exchange for the memory checker and for the Chez back
-- end: three client connections at once against the server, echo of a few
-- sizes (one frame and fragments), pings, a protocol error, and the
-- closing handshake from each side.
import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal
import Data.List
import Network.HTTP.Server
import Network.WebSocket
import System
import System.Concurrency

%default covering

echo : WebSocket -> IO ()
echo ws = do
  Right m <- receive ws
    | Left _ => pure ()
  if messageBytes m == "close please"
     then ignore (closeWebSocket ws 4001 "as asked")
     else do ignore (sendMessage ws m); echo ws

payload : Int -> ByteString
payload n = unsafeCreate n (\b => fill b 0)
  where
    fill : Buffer -> Int -> IO ()
    fill b i = if i >= n then pure () else do setBits8 b i (cast (i `mod` 251)); fill b (i + 1)

client : String -> Int -> IO String
client base k = do
  Right ws <- connectWebSocket ({ config.fragmentSize := 1000 * k } defaultConnectOptions) (base ++ "/")
    | Left e => pure (show e)
  oks <- for [0, 1, 125, 126, 5000, 70000] $ \n => do
    ignore (sendBinary ws (payload n))
    Right m <- receive ws
      | Left i => pure False
    pure (messageBytes m == payload n)
  ignore (ping ws "p")
  ignore (sendText ws "text after a ping")
  Right t <- receive ws
    | Left i => pure (show i)
  r <- if k == 1 then closeWebSocket ws 1000 "client done"
       else do ignore (sendText ws "close please")
               Left i <- receive ws
                 | Right _ => pure (MkCloseInfo 0 "" Nothing False)
               pure i
  pure "client \{show k}: echoes \{show (all id oks)}, \{messageString t}, \{show r}"

main : IO ()
main = do
  Right srv <- startServer (defaultServerConfig (Inet "127.0.0.1" 0)) (\req => pure (acceptWebSocket defaultAcceptOptions req echo))
    | Left e => putStrLn (show e)
  let base = "ws://\{show (serverAddress srv)}"
  results <- makeChannel
  for_ [1, 2, 3] $ \k => fork (do r <- client base k; channelPut results (k, r))
  rs <- for [1, 2, 3] (\_ => channelGet results)
  for_ (sortBy (\a, b => compare (fst a) (fst b)) rs) (putStrLn . snd)
  -- a text message that is not UTF-8, sent as a binary one would be
  Right ws <- connectWebSocket defaultConnectOptions (base ++ "/")
    | Left e => putStrLn (show e)
  ignore (sendMessage ws (TextMessage (pack [0xFF, 0xFE])))
  Left i <- receive ws
    | Right _ => putStrLn "an echo of invalid text"
  putStrLn "invalid text: \{show i}"
  stopServer srv 1000
