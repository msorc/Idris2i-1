module Main

import Data.IORef
import System
import System.Concurrency

-- Test that a condition variable can be used to wake up a green thread.
main : IO ()
main = do
    mutex <- makeMutex
    cond <- makeCondition
    flag <- newIORef False
    tid <- fork $ do
        mutexAcquire mutex
        value <- readIORef flag
        if value
            then pure ()
            else conditionWait cond mutex
        mutexRelease mutex
        putStrLn "child woke up"
    mutexAcquire mutex
    writeIORef flag True
    mutexRelease mutex
    conditionSignal cond
    threadWait tid
    putStrLn "done"
