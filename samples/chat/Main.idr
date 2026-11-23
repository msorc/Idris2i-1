-- A chat room over WebSocket: every message that someone sends goes to
-- everybody in the room.
--
--   chat [PORT]          (8080 by default), then open http://127.0.0.1:PORT/
--
-- `GET /` is a page with a small client in JavaScript, and
-- `GET /chat?name=NAME` the WebSocket of the room.  The program stops on
-- SIGINT, closing the connections with 1001 ("going away").
module Main

import Data.ByteString
import Data.IORef
import Data.Maybe
import Data.SortedMap
import Data.String
import Network.HTTP.Router
import Network.WebSocket
import System
import System.Concurrency
import System.File
import System.Signal

%default covering

-- The people in the room, by the number of their connection.
record Room where
  constructor MkRoom
  lock : Mutex
  people : IORef (SortedMap Int (String, WebSocket))
  next : IORef Int

newRoom : IO Room
newRoom = [| MkRoom makeMutex (newIORef empty) (newIORef 0) |]

-- Send a message to everybody.  The list is taken under the lock, and the
-- sends are made outside it, one connection after the other: a connection
-- that does not take its message within the send timeout fails, and its
-- session leaves the room.
broadcast : Room -> String -> IO ()
broadcast room msg = do
  mutexAcquire room.lock
  ps <- readIORef room.people
  mutexRelease room.lock
  let bytes = fromString msg
  for_ (values ps) $ \(_, ws) => ignore (sendMessage ws (TextMessage bytes))

join : Room -> String -> WebSocket -> IO (Int, Int)
join room name ws = do
  mutexAcquire room.lock
  i <- readIORef room.next
  writeIORef room.next (i + 1)
  modifyIORef room.people (insert i (name, ws))
  n <- (length . Data.SortedMap.toList) <$> readIORef room.people
  mutexRelease room.lock
  pure (i, cast n)

leave : Room -> Int -> IO ()
leave room i = do
  mutexAcquire room.lock
  modifyIORef room.people (delete i)
  mutexRelease room.lock

-- The session of one person: in the thread of the connection, receive
-- and broadcast until the connection ends.
session : Room -> String -> WebSocket -> IO ()
session room name ws = do
  (i, n) <- join room name ws
  ignore (sendText ws ("welcome " ++ name ++ ", " ++ show n ++ " here"))
  broadcast room ("* " ++ name ++ " joined")
  loop
  leave room i
  broadcast room ("* " ++ name ++ " left")
  where
    loop : IO ()
    loop = do
      Right msg <- receive ws
        | Left _ => pure ()
      broadcast room (name ++ ": " ++ messageString msg)
      loop

page : String
page = """
  <!doctype html>
  <title>Chat</title>
  <pre id="log"></pre>
  <form id="f"><input id="m" autofocus size="60"></form>
  <script>
  const name = prompt("Your name?") || "someone";
  const ws = new WebSocket(`ws://${location.host}/chat?name=${encodeURIComponent(name)}`);
  const log = document.getElementById("log");
  ws.onmessage = e => { log.textContent += e.data + "\\n"; };
  ws.onclose = e => { log.textContent += `[closed ${e.code}]\\n`; };
  document.getElementById("f").onsubmit = e => {
    e.preventDefault();
    const m = document.getElementById("m");
    ws.send(m.value); m.value = "";
  };
  </script>
  """

-- Text messages only, of at most 4 KiB; a person who sends nothing for
-- ten minutes is let go; a connection that does not take a message within
-- five seconds is dropped.
options : AcceptOptions
options = { config := { maxMessageSize := 4096, idleTimeout := 600000, sendTimeout := 5000
                      , pingInterval := 30000 } defaultWSConfig } defaultAcceptOptions

routes : Room -> List Route
routes room =
  [ route GET "/" $ \_, _ => pure (bytesResponse statusOK "text/html; charset=utf-8" (fromString page))
  , websocketRoute "/chat" options $ \req, _, ws =>
      session room (fromMaybe "someone" (queryParam "name" req)) ws
  ]

say : String -> IO ()
say s = do putStrLn s; fflush stdout

-- Wait for SIGINT, then say goodbye to everybody and stop.
stopOnInterrupt : Room -> Server -> IO ()
stopOnInterrupt room srv = do
  Just SigINT <- handleNextCollectedSignal
    | _ => do usleep 100000; stopOnInterrupt room srv
  say "interrupted: stopping"
  mutexAcquire room.lock
  ps <- readIORef room.people
  mutexRelease room.lock
  for_ (values ps) $ \(_, ws) => fork (ignore (closeWebSocket ws 1001 "server stopping"))
  stopServer srv 5000

main : IO ()
main = do
  args <- getArgs
  let port = case args of
               (_ :: p :: _) => cast p
               _ => 8080
  room <- newRoom
  Right srv <- startServer (defaultServerConfig (Inet "127.0.0.1" port)) (router (routes room))
    | Left e => do putStrLn "cannot listen on port \{show port}: \{show e}"
                   exitFailure
  say "listening on \{show (serverAddress srv)}"
  Right () <- collectSignal SigINT
    | Left _ => putStrLn "cannot catch SIGINT: stop the server another way"
  _ <- fork (stopOnInterrupt room srv)
  waitServer srv
  say "stopped"
