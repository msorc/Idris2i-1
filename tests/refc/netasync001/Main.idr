-- An echo server on loopback with many concurrent clients, each a green
-- thread doing several round trips.  The waits park green threads instead
-- of blocking workers: the number of OS threads of the process stays near
-- the number of workers.
import Data.Buffer
import Data.IORef
import Data.List
import Data.String
import Network.Socket.Async
import System
import System.Concurrency
import System.File

clients : Nat
clients = 1000

roundTrips : Nat
roundTrips = 5

msgLen : Int
msgLen = 16

-- The number of OS threads of the process (0 where /proc is not there).
osThreads : IO Nat
osThreads = do
  Right s <- readFile "/proc/self/status"
    | Left _ => pure 0
  let ls = lines s
  case find (isPrefixOf "Threads:") ls of
    Just l => pure (cast (trim (substr 8 (length l) l)))
    Nothing => pure 0

-- Echo until the end of the stream.
covering
echo : AsyncSocket -> Buffer -> IO ()
echo s buf = do
  n <- recvCode s buf 0 64 (-1)
  if n <= 0
     then ignore (close s)
     else do r <- sendAllCode s buf 0 n (-1)
             if r < 0 then ignore (close s) else echo s buf

covering
acceptLoop : AsyncSocket -> IO ()
acceptLoop l = do
  Right s <- accept l Nothing
    | Left Closed => pure ()
    | Left e => putStrLn "accept: \{show e}"
  Just buf <- newBuffer 64
    | Nothing => putStrLn "newBuffer"
  _ <- fork (echo s buf)
  acceptLoop l

pad : Nat -> String
pad n = let s = show n in replicate (minus 4 (length s)) '0' ++ s

covering
client : SockAddr -> Nat -> IO Bool
client addr i = do
  Right s <- connect addr Nothing
    | Left e => do putStrLn "connect: \{show e}"; pure False
  Just out <- newBuffer msgLen
    | Nothing => pure False
  Just back <- newBuffer msgLen
    | Nothing => pure False
  ok <- trips s out back roundTrips
  ignore (close s)
  pure ok
  where
    trips : AsyncSocket -> Buffer -> Buffer -> Nat -> IO Bool
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
  workers <- maybe 0 (cast {to = Nat}) <$> getEnv "IDRIS2I_1_WORKERS"
  Right l <- listenOn (Inet "127.0.0.1" 0) 2048
    | Left e => putStrLn "listen: \{show e}"
  Right addr <- localAddress l
    | Left e => putStrLn "localAddress: \{show e}"
  server <- fork (acceptLoop l)
  done <- newIORef False
  maxT <- newIORef 0
  samp <- fork (sampler done maxT)
  results <- makeChannel
  ts <- for [1 .. clients] $ \i =>
          fork (client addr i >>= channelPut results)
  oks <- for [1 .. clients] $ \_ => channelGet results
  for_ ts (\t => threadWait t)
  writeIORef done True
  threadWait samp
  ignore (close l)
  threadWait server
  let good = length (filter id oks)
  putStrLn "\{show good} of \{show clients} clients did \{show roundTrips} round trips"
  m <- readIORef maxT
  -- the workers, the main OS thread, the monitor and the watcher
  let limit = (if workers == 0 then 64 else workers) + 3
  if m <= limit
     then putStrLn "OS threads: within the workers"
     else putStrLn "OS threads: \{show m} (more than \{show limit})"
