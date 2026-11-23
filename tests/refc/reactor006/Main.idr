-- Connections that carry data both ways at once: on each end of each
-- connection, one green thread sends while another one receives on the same
-- socket, with a small send buffer.  Every run must take a fraction of a
-- second: a wakeup missed by the scheduler shows as a run that takes
-- seconds (until a timer or a retransmission happens to rescue it), not
-- only as a hang.
import Data.Buffer
import Data.IORef
import Network.Socket.Async
import System
import System.Clock
import System.Concurrency

connections : Nat
connections = 20

amount : Int
amount = 1048576

piece : Int
piece = 8192

orDie : Show e => String -> IO (Either e a) -> IO a
orDie what act = do
  Right x <- act
    | Left e => do putStrLn "\{what}: \{show e}"; exitFailure
  pure x

covering
sendBytes : AsyncSocket -> Buffer -> Int -> IO ()
sendBytes s buf left = when (left > 0) $ do
  let n = min left piece
  r <- sendAllCode s buf 0 n (-1)
  when (r < 0) $ do putStrLn "send: \{show (codeError r)}"; exitFailure
  sendBytes s buf (left - n)

covering
recvBytes : AsyncSocket -> Buffer -> Int -> IO Int
recvBytes s buf got = do
  n <- recvCode s buf 0 piece (-1)
  if n < 0 then do putStrLn "recv: \{show (codeError n)}"; exitFailure
    else if n == 0 then pure got
    else recvBytes s buf (got + n)

-- Both directions on one socket: returns the bytes received.
covering
both : AsyncSocket -> IO Int
both s = do
  orDie "SendBuffer" (setOption s SendBuffer 4096)
  Just out <- newBuffer piece
    | Nothing => pure (-1)
  Just inp <- newBuffer piece
    | Nothing => pure (-1)
  writer <- fork $ do
    sendBytes s out amount
    orDie "shutdown" (shutdown s ShutWrite)
  got <- recvBytes s inp 0
  threadWait writer
  ignore (close s)
  pure got

covering
serve : AsyncSocket -> Channel Int -> Nat -> IO ()
serve l res Z = pure ()
serve l res (S k) = do
  s <- orDie "accept" (accept l Nothing)
  _ <- fork (both s >>= channelPut res)
  serve l res k

ms : Clock Monotonic -> Integer
ms c = seconds c * 1000 + nanoseconds c `div` 1000000

covering
main : IO ()
main = do
  start <- clockTime Monotonic
  l <- orDie "listen" (listenOn (Inet "127.0.0.1" 0) 64)
  addr <- orDie "localAddress" (localAddress l)
  res <- makeChannel
  server <- fork (serve l res connections)
  for_ [1 .. connections] $ \_ => fork $ do
    s <- orDie "connect" (connect addr Nothing)
    both s >>= channelPut res
  gots <- for [1 .. 2 * connections] $ \_ => channelGet res
  threadWait server
  ignore (close l)
  end <- clockTime Monotonic
  putStrLn "every end received everything: \{show (all (== amount) gots)}"
  let elapsed = ms end - ms start
  when (elapsed > 5000) $ putStrLn "slow: \{show elapsed}ms"
