-- The load generator of the WebSocket benchmark, with the client of the
-- library.
--
--   load PORT echo CONNS MESSAGES SIZE   each connection sends MESSAGES
--                                        binary messages of SIZE bytes, one
--                                        at a time, and waits for each echo
--   load PORT idle CONNS SECONDS         opens CONNS connections, prints
--                                        "open", holds them for SECONDS
--
-- Then it asks the server to stop (`GET /quit`).
import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal
import Data.String
import Network.HTTP.Client
import Network.WebSocket
import System
import System.File
import System.Clock
import System.Concurrency

%default covering

loop : WebSocket -> ByteString -> Int -> IO Int
loop ws msg n =
  if n <= 0 then pure 0 else do
    Right () <- sendBinary ws msg
      | Left _ => pure n
    Right _ <- receive ws
      | Left _ => pure n
    loop ws msg (n - 1)

openAll : String -> Int -> List WebSocket -> IO (List WebSocket)
openAll url n acc =
  if n <= 0 then pure acc else do
    Right ws <- connectWebSocket ({ timeout := 60000 } defaultConnectOptions) url
      | Left e => do putStrLn ("connect: " ++ show e); exitFailure
    openAll url (n - 1) (ws :: acc)

quit : String -> IO ()
quit p = do
  c <- newClient defaultClientConfig
  ignore (httpGet c ("http://127.0.0.1:" ++ p ++ "/quit"))

main : IO ()
main = do
  args <- getArgs
  case args of
    [_, p, "echo", c, m, s] => do
      let url = "ws://127.0.0.1:" ++ p ++ "/"
      let conns = cast {to = Int} c
      let msgs = cast {to = Int} m
      let msg = unsafeCreate (cast s) (\_ => pure ())
      wss <- openAll url conns []
      done <- makeChannel
      t0 <- clockTime Monotonic
      for_ wss $ \ws => fork $ do
        left <- loop ws msg msgs
        channelPut done left
      lefts <- traverse (\_ => channelGet done) wss
      t1 <- clockTime Monotonic
      let ns = toNano (timeDifference t1 t0)
      let n = conns * msgs - sum lefts
      putStrLn "messages \{show n} seconds \{show (cast {to = Double} ns / 1.0e9)}"
      for_ wss $ \ws => ignore (closeWebSocket ws 1000 "")
      quit p
    [_, p, "idle", c, secs] => do
      let url = "ws://127.0.0.1:" ++ p ++ "/"
      wss <- openAll url (cast c) []
      putStrLn "open"
      fflush stdout
      sleep (cast secs)
      for_ wss abort
      quit p
    _ => putStrLn "usage: load PORT echo CONNS MESSAGES SIZE | load PORT idle CONNS SECONDS"
