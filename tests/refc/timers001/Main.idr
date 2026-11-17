-- Timed waits that a signal ends at about the time when their deadline
-- expires, each followed at once by another wait with a deadline: a sleep,
-- which must not end early.  A worker that found the deadline of a thread
-- expired once claimed the thread only after it had released the timer list:
-- in the meantime the signal could wake the thread up, and the thread could
-- run and go to sleep, and then the late claim ended that sleep (and the
-- thread was queued to run while it was still in the timer list).  (The
-- window was narrow: this test caught it reliably only with the window
-- widened by a delay in the runtime, and then the program often hung.)
import Data.IORef
import System
import System.Clock
import System.Concurrency

nanos : Clock type -> Integer
nanos c = seconds c * 1000000000 + nanoseconds c

waiter : Mutex -> Condition -> IORef Int -> Nat -> IO ()
waiter m c early Z = pure ()
waiter m c early (S k) = do
  mutexAcquire m
  conditionWaitTimeout c m 40
  mutexRelease m
  start <- clockTime Monotonic
  usleep 300
  end <- clockTime Monotonic
  when (nanos end - nanos start < 300000) $ do
    mutexAcquire m
    modifyIORef early (+1)
    mutexRelease m
  waiter m c early k

signaller : Condition -> IORef Bool -> IO ()
signaller c done = do
  conditionBroadcast c
  usleep 30
  if !(readIORef done) then pure () else signaller c done

main : IO ()
main = do
  m <- makeMutex
  c <- makeCondition
  early <- newIORef 0
  done <- newIORef False
  signallers <- for [1 .. 3] $ \_ => fork (signaller c done)
  waiters <- for [1 .. 24] $ \_ => fork (waiter m c early 400)
  traverse_ (\t => threadWait t) waiters
  writeIORef done True
  traverse_ (\t => threadWait t) signallers
  putStrLn "sleeps that ended early: \{show !(readIORef early)}"
