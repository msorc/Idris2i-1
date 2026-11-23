-- Transfers through a loopback connection with a small send buffer between
-- two green threads, on more workers than threads: the sends and the
-- receives are partial, the acknowledgements make the sending socket
-- writable while nobody waits for it, and both threads often compute (a
-- checksum) at once.  A parked worker that polled such an event while no
-- thread waited for a descriptor kept watching without a timeout, and
-- nothing woke it up when the threads waited again: nobody polled, and the
-- program hung (in about a third of the runs with 4 workers).
import Data.Bits
import Data.Buffer
import Data.IORef
import Network.Socket.Async
import System
import System.Concurrency

chunk : Int
chunk = 65521

chunks : Int
chunks = 16

orDie : Show e => String -> IO (Either e a) -> IO a
orDie what act = do
  Right x <- act
    | Left e => do putStrLn "\{what}: \{show e}"; exitFailure
  pure x

-- Adler-32 of `len` bytes of the buffer from `i`, from the state (a, b).
adler : Buffer -> Int -> Int -> Int -> Int -> IO (Int, Int)
adler buf i len a b
    = if len <= 0 then pure (a, b) else do
        x <- getBits8 buf i
        let a' = (a + cast x) `mod` 65521
        adler buf (i + 1) (len - 1) a' ((b + a') `mod` 65521)

-- Send the pattern `n` times, with sendCode: count the partial sends.
covering
sendChunks : AsyncSocket -> Buffer -> Int -> IORef Int -> IO ()
sendChunks s buf n partials = when (n > 0) $ do
  sendRange 0 chunk
  sendChunks s buf (n - 1) partials
  where
    sendRange : Int -> Int -> IO ()
    sendRange off len = when (len > 0) $ do
      r <- sendCode s buf off len (-1)
      when (r < 0) $ do putStrLn "send: \{show (codeError r)}"; exitFailure
      when (r < len) $ modifyIORef partials (+ 1)
      sendRange (off + r) (len - r)

covering
receive : AsyncSocket -> Buffer -> Int -> (Int, Int) -> IO (Int, (Int, Int))
receive s buf count (a, b) = do
  n <- recvCode s buf 0 3000 (-1)
  if n < 0
     then do putStrLn "recv: \{show (codeError n)}"; exitFailure
     else if n == 0
       then pure (count, (a, b))
       else do st <- adler buf 0 n a b
               receive s buf (count + n) st

covering
transfer : IO ()
transfer = do
  l <- orDie "listen" (listenOn (Inet "127.0.0.1" 0) 4)
  addr <- orDie "localAddress" (localAddress l)
  Just pat <- newBuffer chunk
    | Nothing => putStrLn "newBuffer"
  for_ [0 .. chunk - 1] $ \i =>
    setBits8 pat i (cast ((i * 7919 + shiftR i 8) .&. 255))
  partials <- newIORef 0
  sender <- fork $ do
    c <- orDie "connect" (connect addr Nothing)
    orDie "SendBuffer" (setOption c SendBuffer 4096)
    sendChunks c pat chunks partials
    orDie "shutdown" (shutdown c ShutWrite)
    ignore (close c)
  s <- orDie "accept" (accept l Nothing)
  Just buf <- newBuffer 3000
    | Nothing => putStrLn "newBuffer"
  (count, (a, b)) <- receive s buf 0 (1, 0)
  threadWait sender
  -- the checksum of the pattern sent `chunks` times
  expected <- repeatAdler pat chunks (1, 0)
  when (count /= chunk * chunks || expected /= (a, b)) $
    putStrLn "received \{show count} bytes of \{show (chunk * chunks)}"
  ignore (close s)
  ignore (close l)
  where
    repeatAdler : Buffer -> Int -> (Int, Int) -> IO (Int, Int)
    repeatAdler pat n (a, b)
        = if n <= 0 then pure (a, b)
          else repeatAdler pat (n - 1) !(adler pat 0 chunk a b)

covering
main : IO ()
main = do
  for_ [1 .. the Nat 6] $ \_ => transfer
  putStrLn "6 transfers done"
