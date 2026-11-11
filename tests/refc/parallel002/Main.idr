module Main

import Data.IORef
import System
import System.Concurrency

-- Threads that update shared state under a mutex, many times, while running
-- in parallel.  The values in the IORef are boxed (they do not fit in 32
-- bits), so that they are allocated and freed by different threads.
main : IO ()
main = do
    mutex <- makeMutex
    counter <- newIORef (the Int 10000000000)
    sumRef <- newIORef (the Integer 0)
    tids <- for [1 .. 8] $ \i => fork $ do
        for_ [1 .. 20000] $ \j => do
            mutexAcquire mutex
            modifyIORef counter (+ 1)
            modifyIORef sumRef (+ cast j)
            mutexRelease mutex
    for_ tids $ \tid => threadWait tid
    readIORef counter >>= printLn
    readIORef sumRef >>= printLn
