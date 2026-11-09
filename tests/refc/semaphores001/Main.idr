module Main

import System
import System.Concurrency

-- Test that a semaphore limits the number of threads in the critical
-- section.
main : IO ()
main = do
    sem <- makeSemaphore 1
    tids <- for [1 .. 3] $ \_ => fork $ do
        semaphoreWait sem
        putStrLn "critical section"
        semaphorePost sem
    for_ tids $ \tid =>
        threadWait tid
    putStrLn "done"
