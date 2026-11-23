-- The WebSocket server of the http library against other implementations:
-- curl (which speaks ws:// since 7.86) as a client, and a peer written in
-- Python with its standard library only (hashlib, base64) as a server for
-- the client of the library.
--
--   main server            serve on a free port, print it, greet each
--                          client and close with 1000; stop after a GET
--                          of /quit
--   main client PORT       connect to a server on PORT, send text and
--                          binary messages, print the echoes and the close
import Data.ByteString
import Data.String
import Network.HTTP.Client
import Network.HTTP.Server
import Network.WebSocket
import System
import System.Concurrency
import System.File

%default covering

greet : WebSocket -> IO ()
greet ws = do
  ignore (sendText ws "hello from idris")
  ignore (sendBinary ws (pack [0, 1, 2, 255]))
  ignore (sendText ws "bye")
  i <- closeWebSocket ws 1000 "done"
  pure ()

serveMode : IO ()
serveMode = do
  quit <- makeChannel
  Right srv <- startServer (defaultServerConfig (Inet "127.0.0.1" 0)) (\req =>
                 if req.path == "/quit" then do channelPut quit (); pure (textResponse statusOK "bye\n")
                 else pure (acceptWebSocket defaultAcceptOptions req greet))
    | Left e => putStrLn (show e)
  putStrLn "port \{show (port (serverAddress srv))}"
  fflush stdout
  channelGet quit
  stopServer srv 1000
  where
    port : SockAddr -> Int
    port (Inet _ p) = p
    port _ = 0

clientMode : String -> IO ()
clientMode p = do
  Right ws <- connectWebSocket ({ subprotocols := ["echo"] } defaultConnectOptions) ("ws://127.0.0.1:" ++ p ++ "/path?q=1")
    | Left e => putStrLn "connect: \{show e}"
  putStrLn "subprotocol: \{show (subprotocol ws)}"
  for_ [TextMessage "hello from idris", TextMessage (fromString "héllo €"), BinaryMessage (pack [0, 255, 128]),
        BinaryMessage (pack (replicate 70000 7))] $ \m => do
    ignore (sendMessage ws m)
    Right e <- receive ws
      | Left i => putStrLn (show i)
    putStrLn "echo: \{show e} same: \{show (e == m)}"
  i <- closeWebSocket ws 1000 "client done"
  putStrLn "client: \{show i}"

main : IO ()
main = do
  args <- getArgs
  case args of
    [_, "server"] => serveMode
    [_, "client", p] => clientMode p
    _ => putStrLn "usage: main server | main client PORT"
