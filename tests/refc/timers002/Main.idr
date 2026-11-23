-- Many threads with deadlines at once: 10000 threads sleep until random
-- deadlines, while others wait on channels and conditions with timeouts
-- that are cancelled early (the value comes first) or that expire.
import Data.IORef
import System
import System.Clock
import System.Concurrency

%foreign "scheme:blodwen-usleep"
         "RefC:refc_usleep"
prim__usleep : Int -> PrimIO ()

-- A small generator, so that the run is the same every time.
next : Int -> Int
next x = (x * 1103515245 + 12345) `mod` 2147483648

sleepers : Int
sleepers = 10000

-- usleep needs a proof that its argument is not negative.
sleepFor : Int -> IO ()
sleepFor us = primIO $ prim__usleep us

main : IO ()
main = do
  m <- makeMutex
  woke <- newIORef (the Int 0)
  -- Sleepers, from 0 to 200ms.
  let forkSleepers : Int -> Int -> List ThreadID -> IO (List ThreadID)
      forkSleepers 0 _ acc = pure acc
      forkSleepers n seed acc = do
        let s = next seed
        t <- fork $ do
          sleepFor (s `mod` 200000)
          mutexAcquire m
          modifyIORef woke (+1)
          mutexRelease m
        forkSleepers (n - 1) s (t :: acc)
  ts <- forkSleepers sleepers 42 []
  -- Channel waits with a long timeout, cancelled early by a value.
  chans <- for [1 .. 1000] $ \_ => makeChannel {a = Int}
  got <- newIORef (the Int 0)
  rs <- for chans $ \c => fork $ do
    Just v <- channelGetWithTimeout c 10000
      | Nothing => pure ()
    mutexAcquire m
    modifyIORef got (+v)
    mutexRelease m
  -- Condition waits with timeouts, half of them signalled.
  cm <- makeMutex
  cv <- makeCondition
  signalled <- newIORef (the Int 0)
  cs <- for [1 .. 1000] $ \i => fork $ do
    mutexAcquire cm
    conditionWaitTimeout cv cm (if i `mod` 2 == 0 then 10000000 else 1000)
    mutexRelease cm
  usleep 20000
  for_ chans $ \c => channelPut c 1
  for_ [1 .. 500] $ \_ => do
    mutexAcquire cm
    conditionSignal cv
    mutexRelease cm
  usleep 50000
  mutexAcquire cm
  conditionBroadcast cv
  mutexRelease cm
  traverse_ (\t => threadWait t) ts
  traverse_ (\t => threadWait t) rs
  traverse_ (\t => threadWait t) cs
  putStrLn "sleepers that woke up: \{show !(readIORef woke)}"
  putStrLn "values received before the timeout: \{show !(readIORef got)}"
