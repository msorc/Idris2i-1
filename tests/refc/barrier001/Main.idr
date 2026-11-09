module Main

import System
import System.Concurrency

-- Test that a barrier releases all the threads that are waiting for it.
main : IO ()
main = do
    barrier <- makeBarrier 3
    tids <- for [1, 2] $ \n => fork $ do
        putStrLn "Hello"
        barrierWait barrier
        putStrLn "Goodbye"
    barrierWait barrier
    putStrLn "Goodbye"
    for_ tids $ \tid =>
        threadWait tid
