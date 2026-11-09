module Main

import System
import System.Concurrency

-- Test that a forked thread runs, and that threadWait waits for it.
main : IO ()
main = do
    tid <- fork $ do
        putStrLn "in child"
    putStrLn "in parent"
    threadWait tid
    putStrLn "parent is done"
