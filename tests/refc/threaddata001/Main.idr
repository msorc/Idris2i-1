module Main

import System
import System.Concurrency

-- Test the thread local data and the thread identifiers.
main : IO ()
main = do
    setThreadData "thread local data"
    stored <- getThreadData String
    putStrLn stored
    mainId <- getThreadId
    tid <- fork $ do
        setThreadData "in the child"
        childStored <- getThreadData String
        putStrLn childStored
        childId <- getThreadId
        putStrLn ("the child has a different id: " ++ show (childId /= mainId))
    threadWait tid
