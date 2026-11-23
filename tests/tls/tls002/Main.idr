-- 200 TLS connections at once, each a green thread doing round trips with
-- an echo server of green threads.  The handshakes and the waits park
-- green threads instead of blocking workers: the number of OS threads of
-- the process stays near the number of workers.
import Data.Buffer
import Data.IORef
import Data.List
import Data.Maybe
import Data.String
import Network.Socket.Async
import Network.TLS
import System
import System.Concurrency
import System.File

clients : Nat
clients = 200

roundTrips : Nat
roundTrips = 5

msgLen : Int
msgLen = 16

-- The number of OS threads of the process (0 where /proc is not there).
osThreads : IO Nat
osThreads = do
  Right s <- readFile "/proc/self/status"
    | Left _ => pure 0
  case find (isPrefixOf "Threads:") (lines s) of
    Just l => pure (cast (trim (substr 8 (length l) l)))
    Nothing => pure 0

covering
echo : TLSSocket -> Buffer -> IO ()
echo s buf = do
  n <- recvCode s buf 0 64 (-1)
  if n <= 0
     then ignore (close s)
     else do r <- sendAllCode s buf 0 n (-1)
             if r < 0 then ignore (close s) else echo s buf

covering
acceptLoop : ServerContext -> AsyncSocket -> IO ()
acceptLoop ctx l = do
  Right sock <- Network.Socket.Async.accept l Nothing
    | Left Closed => pure ()
    | Left e => putStrLn "accept: \{show e}"
  _ <- fork $ do
    Right s <- Network.TLS.accept ctx sock Nothing
      | Left e => putStrLn "server handshake: \{show e}"
    Just buf <- newBuffer 64
      | Nothing => putStrLn "newBuffer"
    echo s buf
  acceptLoop ctx l

pad : Nat -> String
pad n = let s = show n in replicate (minus 4 (length s)) '0' ++ s

covering
client : ClientContext -> SockAddr -> Nat -> IO Bool
client ctx addr i = do
  Right sock <- Network.Socket.Async.connect addr Nothing
    | Left e => do putStrLn "connect: \{show e}"; pure False
  Right s <- Network.TLS.connect ctx "localhost" sock Nothing
    | Left e => do putStrLn "handshake: \{show e}"; pure False
  Just out <- newBuffer msgLen
    | Nothing => pure False
  Just back <- newBuffer msgLen
    | Nothing => pure False
  ok <- trips s out back roundTrips
  ignore (close s)
  pure ok
  where
    trips : TLSSocket -> Buffer -> Buffer -> Nat -> IO Bool
    trips s out back Z = pure True
    trips s out back (S k) = do
      let msg = "client \{pad i} rt \{show k}"
      setString out 0 (substr 0 16 (msg ++ replicate 16 ' '))
      Right () <- sendAll s out 0 msgLen Nothing
        | Left e => do putStrLn "send: \{show e}"; pure False
      Right n <- recvExactly s back 0 msgLen Nothing
        | Left e => do putStrLn "recv: \{show e}"; pure False
      a <- getString out 0 msgLen
      b <- getString back 0 msgLen
      if n == msgLen && a == b
         then trips s out back k
         else do putStrLn "client \{show i}: sent \{show a}, got \{show b}"
                 pure False

covering
sampler : IORef Bool -> IORef Nat -> IO ()
sampler done maxT = do
  n <- osThreads
  modifyIORef maxT (max n)
  usleep 2000
  if !(readIORef done) then pure () else sampler done maxT

covering
main : IO ()
main = do
  [_, certs] <- getArgs
    | _ => putStrLn "usage: main <certs>"
  workers <- maybe 0 (cast {to = Nat}) <$> getEnv "IDRIS2_WORKERS"
  Right sctx <- newServerContext (serverConfig (credentialFiles (certs ++ "/server.pem") (certs ++ "/server.key")))
    | Left e => putStrLn "server context: \{show e}"
  Right cctx <- newClientContext ({ trust := [CAFile (certs ++ "/ca.pem")] } defaultClientConfig)
    | Left e => putStrLn "client context: \{show e}"
  Right l <- listenOn (Inet "127.0.0.1" 0) 1024
    | Left e => putStrLn "listen: \{show e}"
  Right addr <- localAddress l
    | Left e => putStrLn "localAddress: \{show e}"
  server <- fork (acceptLoop sctx l)
  done <- newIORef False
  maxT <- newIORef 0
  samp <- fork (sampler done maxT)
  results <- makeChannel
  ts <- for [1 .. clients] $ \i =>
          fork (do pure (); client cctx addr i >>= channelPut results)
  oks <- for [1 .. clients] $ \_ => channelGet results
  for_ ts (\t => threadWait t)
  writeIORef done True
  threadWait samp
  ignore (Network.Socket.Async.close l)
  threadWait server
  let good = length (filter id oks)
  putStrLn "\{show good} of \{show clients} clients did \{show roundTrips} round trips"
  m <- readIORef maxT
  -- the workers, the main OS thread, the monitor and the watcher
  let limit = (if workers == 0 then 64 else workers) + 3
  if m <= limit
     then putStrLn "OS threads: within the workers"
     else putStrLn "OS threads: \{show m} (more than \{show limit})"
