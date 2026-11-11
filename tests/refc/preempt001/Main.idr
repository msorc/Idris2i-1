module Main

import Data.IORef
import System
import System.Concurrency

-- More threads that compute than workers: a thread that computes for long
-- yields (at the end of an iteration of its loop) when other threads wait
-- for its worker, so the main thread keeps running while they compute.
spin : Int -> Int -> Int
spin 0 acc = acc
spin n acc = spin (n - 1) (if acc `mod` 7 == 3 then acc + n else acc - 1)

main : IO ()
main = do
    mutex <- makeMutex
    finished <- newIORef (the Int 0)
    done <- makeChannel
    for_ [1 .. 4] $ \i => fork $ do
        pure ()
        let r = spin 200000000 i
        mutexAcquire mutex
        modifyIORef finished (+ 1)
        mutexRelease mutex
        channelPut done r
    for_ [1 .. 20] $ \_ => usleep 1000
    n <- readIORef finished
    putStrLn ("computations finished while the main thread slept: " ++ show n)
    for_ [1 .. 4] $ \_ => channelGet done
    putStrLn "done"
