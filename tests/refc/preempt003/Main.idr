-- With a single worker, a thread that computes is preempted for a thread
-- whose sleep is over, at its next safepoint: also when it computes in
-- functions that call each other in tail position (no loop), or in a deep
-- recursion that is not a tail call.
import Data.IORef
import System
import System.File
import System.Concurrency

lcg : Int -> Int
lcg v = v * 6364136223846793005 + 1442695040888963407

mutual
  ping : IORef Int -> Int -> IO ()
  ping ref 0 = pure ()
  ping ref n = do modifyIORef ref lcg
                  pong ref (n - 1)
  pong : IORef Int -> Int -> IO ()
  pong ref 0 = pure ()
  pong ref n = do modifyIORef ref lcg
                  ping ref (n - 1)

-- Not a tail call: the stack grows.
deep : Int -> Int
deep 0 = 0
deep n = lcg (deep (n - 1))

say : String -> IO ()
say m = do putStrLn m; fflush stdout

run : String -> IO () -> IO ()
run what spin = do
  -- before the fork, so that the order of the lines does not depend on which
  -- of two sleeps ends first on a busy machine
  say "main: \{what}"
  t <- fork $ do usleep 2000
                 say "printer: woke up"
  spin
  say "main: done"
  threadWait t

main : IO ()
main = do
  ref <- newIORef 0
  run "mutual recursion" (ping ref 20000000)
  run "deep recursion" (do r <- pure (deep 20000000); writeIORef ref r)
