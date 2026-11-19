module Single

-- The System.Concurrency primitives in a program that has one thread, as on
-- Node: the same output on Chez, RefC and Node.

import Data.IORef
import System
import System.Concurrency

say : String -> IO ()
say = putStrLn

main : IO ()
main = do
  -- mutexes are recursive
  m <- makeMutex
  mutexAcquire m
  mutexAcquire m
  mutexRelease m
  mutexRelease m
  say "mutex"
  ref <- newIORef (the Int 0)
  atomically m (modifyIORef ref (+ 5))
  atomically m (atomically m (modifyIORef ref (* 3)))
  say ("atomically: " ++ show !(readIORef ref))

  -- semaphores count
  s <- makeSemaphore 2
  semaphoreWait s
  semaphorePost s
  semaphorePost s
  semaphoreWait s
  semaphoreWait s
  say "semaphore"

  -- a channel holds one value
  c <- makeChannel
  channelPut c "one"
  say !(channelGet c)
  channelPut c "two"
  say (show !(channelGetNonBlocking c))
  say (show !(channelGetNonBlocking c))
  say (show !(channelGetWithTimeout c 20))
  channelPut c "three"
  say (show !(channelGetWithTimeout c 20))

  -- a barrier for one thread does not wait
  b <- makeBarrier 1
  barrierWait b
  say "barrier"

  -- conditions with nobody to wait for
  cv <- makeCondition
  conditionSignal cv
  conditionBroadcast cv
  mutexAcquire m
  conditionWaitTimeout cv m 20000
  mutexRelease m
  say "condition"

  -- thread data of the one thread
  setThreadData (the Int 42)
  d <- getThreadData Int
  say ("thread data: " ++ show d)
  setThreadData "text"
  d <- getThreadData String
  say ("thread data: " ++ d)
