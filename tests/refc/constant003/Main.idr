-- Global IORefs, made by top-level constants, which the forked threads and
-- the main thread ask for at the same time: they must all get the same
-- IORefs.  The main thread, whose identifier is 0, once took a constant that
-- another thread had just started to evaluate for one that it evaluated
-- itself.  (The window was narrow: this test caught it reliably only with
-- the window widened by a delay in the runtime.)
-- (The initial values differ, or the IORefs would be one and the same.)
import Data.IORef
import System.Concurrency

counter0 : IORef Int
counter0 = unsafePerformIO (newIORef 0)

counter1 : IORef Int
counter1 = unsafePerformIO (newIORef 1)

counter2 : IORef Int
counter2 = unsafePerformIO (newIORef 2)

counter3 : IORef Int
counter3 = unsafePerformIO (newIORef 3)

counter4 : IORef Int
counter4 = unsafePerformIO (newIORef 4)

counter5 : IORef Int
counter5 = unsafePerformIO (newIORef 5)

counter6 : IORef Int
counter6 = unsafePerformIO (newIORef 6)

counter7 : IORef Int
counter7 = unsafePerformIO (newIORef 7)

counter8 : IORef Int
counter8 = unsafePerformIO (newIORef 8)

counter9 : IORef Int
counter9 = unsafePerformIO (newIORef 9)

counter10 : IORef Int
counter10 = unsafePerformIO (newIORef 10)

counter11 : IORef Int
counter11 = unsafePerformIO (newIORef 11)

counter12 : IORef Int
counter12 = unsafePerformIO (newIORef 12)

counter13 : IORef Int
counter13 = unsafePerformIO (newIORef 13)

counter14 : IORef Int
counter14 = unsafePerformIO (newIORef 14)

counter15 : IORef Int
counter15 = unsafePerformIO (newIORef 15)

-- A function, not a constant: every call asks for the IORefs.
%noinline
counters : Int -> List (IORef Int)
counters _ =
  [counter0, counter1, counter2, counter3, counter4, counter5, counter6, counter7,
   counter8, counter9, counter10, counter11, counter12, counter13, counter14, counter15]

%noinline
bump : Mutex -> IO ()
bump m = do
  -- (in the action, so that a forked thread asks for the IORefs itself)
  n <- getThreadId
  let refs = counters n
  mutexAcquire m
  for_ refs $ \r => modifyIORef r (+1)
  mutexRelease m

main : IO ()
main = do
  m <- makeMutex
  ts <- for [1 .. 3] $ \_ => fork (bump m)
  bump m
  traverse_ (\t => threadWait t) ts
  vs <- traverse readIORef (counters 0)
  printLn vs
