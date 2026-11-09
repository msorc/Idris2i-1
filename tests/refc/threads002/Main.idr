module Main

import System
import System.Concurrency

-- Test that several green threads can be forked, and that waiting for all
-- of them works.
main : IO ()
main = do
    tids <- for [1 .. 5] $ \i => fork $ do
        putStrLn ("thread " ++ show i)
    for_ tids $ \tid =>
        threadWait tid
    putStrLn "all threads are done"
