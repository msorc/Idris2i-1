module Main

import System
import System.Concurrency

-- Test that values can be passed from one green thread to another through a
-- channel.
main : IO ()
main = do
    chan <- makeChannel
    tid <- fork $ do
        channelPut chan "Hello"
        channelPut chan "Goodbye"
    first <- channelGet chan
    putStrLn first
    second <- channelGet chan
    putStrLn second
    threadWait tid
