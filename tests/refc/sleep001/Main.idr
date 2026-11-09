module Main

import System
import System.Concurrency

-- Test that a sleeping green thread does not stop the other ones from
-- making progress.
main : IO ()
main = do
    tid <- fork $ do
        sleep 1
        putStrLn "the child slept for a second"
    putStrLn "the main thread did not wait"
    threadWait tid
