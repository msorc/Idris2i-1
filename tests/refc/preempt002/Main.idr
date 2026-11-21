module Main

import Data.IORef
import System
import System.Concurrency

-- As many threads that compute as workers: a thread that sleeps, or waits
-- with a timeout, wakes up when its time is over, not once a thread that
-- computes blocks or ends.  The threads that compute (the main one and
-- `n - 1` forked ones) stop when told to, or after a few seconds; the
-- sleeper waits for a tenth of a second, three times, and tells them.
spin : Int -> Int -> Int
spin 0 acc = acc
spin n acc = spin (n - 1) (if acc `mod` 7 == 3 then acc + n else acc - 1)

compute : Mutex -> IORef Bool -> IORef Int -> Int -> Int -> IO ()
compute mutex stop finished chunks acc = do
    mutexAcquire mutex
    stopped <- readIORef stop
    mutexRelease mutex
    if stopped || chunks == 0
       then do
         mutexAcquire mutex
         modifyIORef finished (+ 1)
         mutexRelease mutex
       else compute mutex stop finished (chunks - 1) (spin 1000000 acc)

report : Mutex -> IORef Int -> String -> IO ()
report mutex finished what = do
    mutexAcquire mutex
    n <- readIORef finished
    mutexRelease mutex
    putStrLn "\{what}: \{if n == 0 then "no computation" else show n ++ " computation(s)"} finished"

sleeper : Mutex -> IORef Bool -> IORef Int -> IO ()
sleeper mutex stop finished = do
    usleep 100000
    report mutex finished "after a sleep"
    condition <- makeCondition
    mutexAcquire mutex
    conditionWaitTimeout condition mutex 100000
    mutexRelease mutex
    report mutex finished "after a timed wait"
    _ <- channelGetWithTimeout (the (Channel ()) !makeChannel) 100
    report mutex finished "after a timed channel get"
    mutexAcquire mutex
    writeIORef stop True
    mutexRelease mutex

main : IO ()
main = do
    [_, sn] <- getArgs
      | _ => putStrLn "usage: main <threads that compute>"
    mutex <- makeMutex
    stop <- newIORef False
    finished <- newIORef (the Int 0)
    -- (it starts at once, and sleeps)
    s <- fork (sleeper mutex stop finished)
    let n = cast {to = Int} sn
    threads <- if n > 1
                  then for [2 .. n] $ \i =>
                         fork (compute mutex stop finished 1000 i)
                  else pure []
    compute mutex stop finished 1000 1
    threadWait s
    for_ threads $ \t => threadWait t
    putStrLn "done"
