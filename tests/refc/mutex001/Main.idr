module Main

import Data.IORef
import System
import System.Concurrency

-- Test that a mutex excludes other green threads from the critical section.
main : IO ()
main = do
    mutex <- makeMutex
    counter <- newIORef 0
    tids <- for [1 .. 4] $ \_ => fork $ do
        for_ [1 .. 100] $ \_ => do
            mutexAcquire mutex
            value <- readIORef counter
            writeIORef counter (value + 1)
            mutexRelease mutex
    for_ tids $ \tid =>
        threadWait tid
    value <- readIORef counter
    putStrLn ("counter = " ++ show value)
