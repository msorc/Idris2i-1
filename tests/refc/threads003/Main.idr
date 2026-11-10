module Main

import System
import System.Concurrency

-- Like in the Chez backend, the program ends when the main expression is
-- done: the other threads are abandoned, whether they are blocked forever
-- or merely sleeping, and the program exits normally.
main : IO ()
main = do
    chan <- makeChannel {a = String}
    _ <- fork $ do
        v <- channelGet chan
        putStrLn ("never printed: " ++ v)
    _ <- fork $ do
        usleep 100000
        putStrLn "never printed: the sleeping thread was abandoned"
    putStrLn "main is done"
