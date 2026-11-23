-- Graceful shutdown: idle persistent connections are closed at once, a
-- request in progress finishes (with `Connection: close`), new connections
-- are refused, and a request that does not finish within the grace period
-- is cut off.
import Data.ByteString
import Data.IORef
import HttpTest
import Network.HTTP.Client
import Network.HTTP.Server
import System
import System.Concurrency

%default covering

app : Handler
app req =
  if req.path == "/slow" then do
    usleep 500000
    pure (textResponse statusOK "slow done\n")
  else if req.path == "/stuck" then do
    sleep 5
    pure (textResponse statusOK "too late\n")
  else pure (textResponse statusOK "hello\n")

elapsedMs : Int -> IO Int
elapsedMs t0 = do t <- now; pure ((t - t0) `div` 1000000)

-- A request in a thread of its own; its outcome is put in the channel.
background : Channel String -> SockAddr -> String -> IO ()
background ch a path = do
  c <- newClient defaultClientConfig
  r <- httpGet c "http://\{show a}\{path}"
  channelPut ch $ case r of
    Right rep => "\{path}: \{show rep.status.code} connection=\{show (lookupHeader "connection" rep.headers)} \{show rep.body}"
    Left e => "\{path}: error \{show e}"

main : IO ()
main = do
  srv <- orDie "start" (startServer (defaultServerConfig (Inet "127.0.0.1" 0)) app)
  let a = serverAddress srv
  -- an idle persistent connection
  idle <- orDie "connect" (connect a Nothing)
  sendRaw idle "GET /hello HTTP/1.1\r\nHost: x\r\n\r\n"
  _ <- readUntil idle "hello\n" 2000
  -- a request in progress
  ch <- makeChannel
  _ <- fork (background ch a "/slow")
  usleep 100000
  n <- openConnections srv
  putStrLn "open connections before the shutdown: \{show n}"
  t0 <- now
  _ <- fork (stopServer srv 3000)
  -- the idle connection is closed without waiting for the slow request
  (_, ended) <- readUntilEnd idle 2000
  ms <- elapsedMs t0
  putStrLn "idle connection closed: \{show ended}, at once: \{show (ms < 400)}"
  ignore (close idle)
  r <- channelGet ch
  putStrLn r
  waitServer srv
  ms <- elapsedMs t0
  putStrLn "stopped after the slow request, within the grace: \{show (ms >= 300 && ms < 2500)}"
  r <- connect a Nothing
  putStrLn ("connect after the shutdown: " ++ either (const "refused") (const "accepted") r)
  -- a request that does not finish within the grace period
  srv <- orDie "start" (startServer (defaultServerConfig (Inet "127.0.0.1" 0)) app)
  _ <- fork (background ch (serverAddress srv) "/stuck")
  usleep 100000
  t0 <- now
  stopServer srv 300
  ms <- elapsedMs t0
  putStrLn "stopped at the end of the grace: \{show (ms >= 250 && ms < 2000)}"
  r <- channelGet ch
  putStrLn r
