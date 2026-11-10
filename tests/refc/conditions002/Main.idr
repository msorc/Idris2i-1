module Main

import System
import System.Concurrency

busy : Int -> Int -> Int
busy 0 acc = acc
busy n acc = busy (n - 1) (acc + n `mod` 7)

main : IO ()
main = do
    mutex <- makeMutex
    cond <- makeCondition
    -- Waiting on a condition releases the mutex completely, even when it is
    -- held recursively, and restores it afterwards.
    tid <- fork $ do
        mutexAcquire mutex
        mutexAcquire mutex
        conditionWait cond mutex
        mutexRelease mutex
        mutexRelease mutex
        putStrLn "woken up while holding the mutex twice"
    mutexAcquire mutex
    conditionSignal cond
    mutexRelease mutex
    threadWait tid
    -- A thread whose timed wait has expired must leave the condition, even
    -- when another thread signals it before it gets to run.  Threads only
    -- switch when they block, so the worker starts once the main thread is
    -- waiting, and it keeps the CPU until the timeout has expired.  The
    -- signaller then wakes up at the same time as the main thread.
    worker <- fork $ do
        usleep 10
        printLn (busy 1000000 0 > 0)
        signaller <- fork $ do
            usleep 1
            conditionSignal cond
            putStrLn "signalled"
        pure ()
    mutexAcquire mutex
    conditionWaitTimeout cond mutex 1000
    mutexRelease mutex
    putStrLn "timed out"
    threadWait worker
