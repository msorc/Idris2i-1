-- An echo server with a few clients, on the Chez back end, whose threads
-- are OS threads: the waits block their thread in poll(2).
import Data.Buffer
import Data.List
import Network.Socket.Async
import System
import System.Concurrency

clients : Nat
clients = 4

roundTrips : Nat
roundTrips = 3

covering
echo : AsyncSocket -> Buffer -> IO ()
echo s buf = do
  n <- recvCode s buf 0 64 (-1)
  if n <= 0
     then ignore (close s)
     else do r <- sendAllCode s buf 0 n (-1)
             if r < 0 then ignore (close s) else echo s buf

-- Accept `n` connections.
covering
acceptN : AsyncSocket -> Nat -> IO ()
acceptN l Z = pure ()
acceptN l (S k) = do
  Right s <- accept l Nothing
    | Left e => putStrLn "accept: \{show e}"
  Just buf <- newBuffer 64
    | Nothing => putStrLn "newBuffer"
  _ <- fork (echo s buf)
  acceptN l k

covering
client : SockAddr -> Nat -> IO Bool
client addr i = do
  Right s <- connect addr Nothing
    | Left e => do putStrLn "connect: \{show e}"; pure False
  Just buf <- newBuffer 16
    | Nothing => pure False
  ok <- trips s buf roundTrips
  ignore (close s)
  pure ok
  where
    trips : AsyncSocket -> Buffer -> Nat -> IO Bool
    trips s buf Z = pure True
    trips s buf (S k) = do
      let msg = "client \{show i} trip \{show k}"
          len = stringByteLength msg
      setString buf 0 msg
      Right () <- sendAll s buf 0 len Nothing
        | Left e => do putStrLn "send: \{show e}"; pure False
      d <- deadlineIn 5000000000
      Right n <- recvExactly s buf 0 len (Just d)
        | Left e => do putStrLn "recv: \{show e}"; pure False
      back <- getString buf 0 n
      if back == msg then trips s buf k else pure False

covering
main : IO ()
main = do
  Right l <- listenOn (Inet "127.0.0.1" 0) 16
    | Left e => putStrLn "listen: \{show e}"
  Right addr <- localAddress l
    | Left e => putStrLn "localAddress: \{show e}"
  server <- fork (acceptN l clients)
  results <- makeChannel
  ts <- for [1 .. clients] $ \i => fork (client addr i >>= channelPut results)
  oks <- for [1 .. clients] $ \_ => channelGet results
  for_ ts (\t => threadWait t)
  threadWait server
  putStrLn "\{show (length (filter id oks))} of \{show clients} clients did \{show roundTrips} round trips"
  -- a deadline
  Right c <- connect addr Nothing
    | Left e => putStrLn "connect: \{show e}"
  Just buf <- newBuffer 8
    | Nothing => putStrLn "newBuffer"
  d <- deadlineIn 50000000
  r <- recv c buf 0 8 (Just d)
  putStrLn "recv from a silent peer: \{either show show r}"
  ignore (close c)
  ignore (close l)
