-- A thread that waits for a pipe is served while other threads compute
-- without blocking on every worker: the runtime makes one of them yield to
-- look at the descriptors.
import Data.Buffer
import Data.IORef
import System
import System.Concurrency
import System.IO.Fd

-- (a loop: it has a safepoint, where it yields when asked to)
spin : Int -> Int -> Int
spin 0 acc = acc
spin n acc = spin (n - 1) (if acc `mod` 7 == 3 then acc + n else acc - 1)

compute : IORef Bool -> Int -> IO Int
compute stop n = do
  let r = spin 10000000 n
  if !(readIORef stop) then pure r else compute stop (r `mod` 1000)

main : IO ()
main = do
  args <- getArgs
  let computers = case args of
                    [_, n] => cast n
                    _ => 1
  Right (r, w) <- pipe
    | Left e => die "pipe: \{show e}"
  ignore $ setNonBlocking r
  ignore $ setNonBlocking w
  stop <- newIORef False
  waiter <- fork $ do
    Just buf <- newBuffer 1
      | Nothing => die "newBuffer"
    1 <- readFdWait r buf 0 1
      | k => die "read: \{show k}"
    putStrLn "the waiter got its byte while the others computed: \{show (not !(readIORef stop))}"
    -- (with a single worker, the main thread would only run once the
    -- threads that compute are done)
    writeIORef stop True
  writer <- fork $ do
    usleep 50000
    Just buf <- newBuffer 1
      | Nothing => die "newBuffer"
    1 <- writeFdWait w buf 0 1
      | k => die "write: \{show k}"
    pure ()
  start <- now
  cs <- for [1 .. computers] $ \_ => fork (ignore $ compute stop 0)
  threadWait waiter
  traverse_ (\t => threadWait t) cs
  end <- now
  threadWait writer
  putStrLn "within 2s: \{show (end - start < 2000000000)}"
