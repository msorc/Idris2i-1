-- Drive the chat sample: 200 people join, each sends one message, and
-- every one of them must get all 200; then the limits, the page, and the
-- goodbye of the server when it stops.
import Data.ByteString
import Data.List
import Data.String
import Network.HTTP.Client
import Network.WebSocket
import System
import System.Concurrency
import System.File

%default covering

people : Int
people = 200

say : String -> IO ()
say s = do putStrLn s; fflush stdout

enter : String -> Int -> IO WebSocket
enter base i = do
  Right ws <- connectWebSocket defaultConnectOptions (base ++ "/chat?name=p" ++ show i)
    | Left e => do say "p\{show i}: \{show e}"; exitFailure
  -- the welcome comes once the server has put us in the room
  Right m <- receive ws
    | Left c => do say "p\{show i}: \{show c}"; exitFailure
  pure ws

-- Receive until the messages of all the people have come: how many came.
collect : WebSocket -> Int -> Int -> IO Int
collect ws dl got =
  if got >= people then pure got else do
    Just (Right m) <- receiveBefore ws dl
      | _ => pure got
    let s = messageString m
    collect ws dl (if isInfixOf ": hello from p" s then got + 1 else got)

main : IO ()
main = do
  [_, port] <- getArgs
    | _ => say "usage: client PORT"
  let base = "ws://127.0.0.1:" ++ port
  wss <- traverse (enter base) [0 .. people - 1]
  done <- makeUnboundedChannel
  dl <- deadlineAfterMs 60000
  for_ (zip [0 .. people - 1] wss) $ \(i, ws) => fork $ do
    ignore (sendText ws ("hello from p" ++ show i))
    n <- collect ws dl 0
    channelPut done n
  counts <- traverse (\_ => channelGet done) wss
  let short = filter (< people) counts
  say (if isNil short then "\{show people} people: every one got the \{show people} messages"
       else "\{show (length short)} people missed messages: \{show short}")
  for_ wss $ \ws => fork (ignore (closeWebSocket ws 1000 "bye"))

  -- a message over the limit of the room (4 KiB)
  ws <- enter base 1000
  ignore (sendText ws (pack (replicate 5000 'x')))
  r <- receiveAll ws
  say "a message of 5000 bytes: \{show r}"

  -- the page
  c <- newClient defaultClientConfig
  Right p <- httpGet c ("http://127.0.0.1:" ++ port ++ "/")
    | Left e => say (show e)
  say "GET /: \{show p.status.code} \{show (lookupHeader "content-type" p.headers)}"

  -- the goodbye when the server stops
  ws <- enter base 2000
  say "waiting"
  r <- receiveAll ws
  say "when the server stops: \{show r}"
  where
    receiveAll : WebSocket -> IO CloseInfo
    receiveAll ws = do
      Right _ <- receive ws
        | Left i => pure i
      receiveAll ws
