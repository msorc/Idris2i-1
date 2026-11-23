-- An echo server for the WebSocket benchmark: every message is sent back.
-- `server PORT [channel]`; prints "listening" when it is ready, stops after
-- a request for `/quit`.  With `channel`, the echoes are sent by a writer
-- thread of each connection, fed by a channel, instead of by the receiver
-- (to compare a single writer with the lock of the library).
import Data.String
import Network.HTTP.Server
import Network.WebSocket
import System
import System.File
import System.Concurrency

%default covering

echo : WebSocket -> IO ()
echo ws = do
  Right m <- receive ws
    | Left _ => pure ()
  Right () <- sendMessage ws m
    | Left _ => pure ()
  echo ws

-- The receiver puts the messages in a channel, and a thread sends them.
writer : WebSocket -> Channel (Maybe Message) -> IO ()
writer ws ch = do
  Just m <- channelGet ch
    | Nothing => pure ()
  ignore (sendMessage ws m)
  writer ws ch

echoVia : WebSocket -> IO ()
echoVia ws = do
  ch <- makeBufferedChannel 64
  done <- makeChannel
  _ <- fork (do writer ws ch; channelPut done ())
  loop ch
  channelPut ch Nothing
  channelGet done
  where
    loop : Channel (Maybe Message) -> IO ()
    loop ch = do
      Right m <- receive ws
        | Left _ => pure ()
      channelPut ch (Just m)
      loop ch

main : IO ()
main = do
  (p, session) <- the (IO (String, WebSocket -> IO ())) $ case !getArgs of
    [_, p] => pure (p, echo)
    [_, p, "channel"] => pure (p, echoVia)
    _ => do putStrLn "usage: server PORT [channel]"; exitFailure
  let cfg = { maxConnections := 100000, idleTimeout := 600000 } (defaultServerConfig (Inet "127.0.0.1" (cast p)))
  quit <- makeChannel
  Right srv <- startServer cfg (\req =>
                 if req.path == "/quit"
                    then do channelPut quit (); pure (textResponse statusOK "bye\n")
                    else pure (acceptWebSocket defaultAcceptOptions req session))
    | Left e => putStrLn (show e)
  putStrLn "listening"
  fflush stdout
  channelGet quit
  stopServer srv 100
