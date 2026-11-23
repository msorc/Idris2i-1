-- Keep-alive pings, the idle timeout, and backpressure: a peer that does
-- not answer pings is dropped, one that answers stays; a connection without
-- messages is closed; a sender to a peer that does not read waits and then
-- fails instead of queueing; and the receiver goes on (its pongs are not
-- held up) while a sender is stuck.
import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal
import Data.IORef
import Data.List
import Data.String
import HttpTest
import Network.HTTP.Server
import Network.WebSocket
import Network.WebSocket.Handshake
import System
import System.Concurrency
import WsTest

%default covering

keepAlive : WSConfig
keepAlive = { pingInterval := 200, pongTimeout := 400 } defaultWSConfig

receiveAll : WebSocket -> IO CloseInfo
receiveAll ws = do
  Right _ <- receive ws
    | Left i => pure i
  receiveAll ws

-- Send messages of 64 KiB until a send fails: how many bytes went out.
flood : WebSocket -> ByteString -> Int -> IO (Int, WSError)
flood ws chunk sent = do
  Right () <- sendBinary ws chunk
    | Left e => pure (sent, e)
  flood ws chunk (sent + lengthInt chunk)

chunk : ByteString
chunk = unsafeCreate 65536 (\_ => pure ())

-- A server after its `101` that does nothing for two seconds.
silentServer : Request -> Response
silentServer req =
  case checkHandshake defaultAcceptOptions req of
    Left r => r
    Right h => respond statusSwitchingProtocols
                 (headersFromPairs [("Upgrade", "websocket"), ("Connection", "Upgrade"),
                                    ("Sec-WebSocket-Accept", acceptKey h.key)])
                 (UpgradeBody (\_ => usleep 2000000))

accept : WSConfig -> Request -> (WebSocket -> IO ()) -> IO Response
accept cfg req session = pure (acceptWebSocket ({ config := cfg } defaultAcceptOptions) req session)

handler : Channel String -> Handler
handler ev req =
  if req.path == "/ka" then accept keepAlive req $ \ws => do
    i <- receiveAll ws
    n <- pongCount ws
    channelPut ev ("server: \{show i}; at least 3 pongs: \{show (n >= 3)}")
  else if req.path == "/idle" then accept ({ idleTimeout := 300 } defaultWSConfig) req $ \ws => do
    i <- receiveAll ws
    channelPut ev ("server: \{show i}")
  else if req.path == "/flood" then accept ({ sendTimeout := 500 } defaultWSConfig) req $ \ws => do
    (n, e) <- flood ws chunk 0
    channelPut ev ("server: the send failed with \"\{show e}\" after less than 64 MiB: \{show (n < 67108864)}")
  else if req.path == "/stuck" then accept ({ sendTimeout := 0, closeTimeout := 300 } defaultWSConfig) req $ \ws => do
    stopped <- makeChannel
    _ <- fork $ do
      (_, e) <- flood ws chunk 0
      channelPut stopped ()
    Right m <- receive ws
      | Left i => channelPut ev ("server: \{show i}")
    channelPut ev ("server: the receiver got \{show (messageString m)} while a sender is stuck")
    i <- closeWebSocket ws 1000 ""
    channelGet stopped
    channelPut ev ("server: \{show i}; the stuck sender returned")
  else if req.path == "/silent" then pure (silentServer req)
  else pure (statusResponse statusNotFound)

main : IO ()
main = do
  ev <- makeUnboundedChannel
  Right srv <- startServer (defaultServerConfig (Inet "127.0.0.1" 0)) (handler ev)
    | Left e => putStrLn (show e)
  let addr = serverAddress srv
  let base = "ws://\{show addr}"

  putStrLn "a peer that does not answer pings"
  r <- rawOpen addr "/ka"
  printUntilEnd r 3000
  rawClose r
  putStrLn !(channelGet ev)

  putStrLn "a peer that answers pings"
  Right ws <- connectWebSocket defaultConnectOptions (base ++ "/ka")
    | Left e => putStrLn (show e)
  got <- makeChannel
  _ <- fork (do i <- receiveAll ws; channelPut got i)
  usleep 1500000
  i <- closeWebSocket ws 1000 "enough"
  putStrLn "client: \{show i}"
  i <- channelGet got
  putStrLn !(channelGet ev)

  putStrLn "idle timeout"
  Right ws <- connectWebSocket defaultConnectOptions (base ++ "/idle")
    | Left e => putStrLn (show e)
  i <- receiveAll ws
  putStrLn "client: \{show i}"
  putStrLn !(channelGet ev)

  putStrLn "keep-alive of the client against a server that does not answer"
  Right ws <- connectWebSocket ({ config := keepAlive } defaultConnectOptions) (base ++ "/silent")
    | Left e => putStrLn (show e)
  i <- receiveAll ws
  putStrLn "client: \{show i}"

  putStrLn "a peer that does not read"
  r <- rawOpen addr "/flood"
  putStrLn !(channelGet ev)
  rawClose r

  putStrLn "a peer that does not read, but sends a ping and a message"
  r <- rawOpen addr "/stuck"
  usleep 300000
  sendFrame r 0x89 True "are you there"
  sendFrame r 0x81 True "still here"
  putStrLn !(channelGet ev)
  putStrLn !(channelGet ev)
  rawClose r

  stopServer srv 1000
