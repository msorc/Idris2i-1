module Main

import System.Concurrency

-- Test that reading the thread local data does not consume it, and that a
-- forked thread inherits the data of its parent (as in the Chez backend).
main : IO ()
main = do
    setThreadData "kept"
    first <- getThreadData String
    second <- getThreadData String
    putStrLn (first ++ " " ++ second)
    tid <- fork $ do
        inherited <- getThreadData String
        putStrLn ("child inherited: " ++ inherited)
        setThreadData "changed by the child"
    threadWait tid
    after <- getThreadData String
    putStrLn ("parent still has: " ++ after)
