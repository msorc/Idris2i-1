module Main

import System.Concurrency

-- Like in the Chez backend, a channel holds one value: putting a value into
-- an empty channel does not wait for a receiver.
main : IO ()
main = do
    chan <- makeChannel
    channelPut chan "stored"
    value <- channelGet chan
    putStrLn value
    channelPut chan "picked up without blocking"
    Just v <- channelGetNonBlocking chan
        | Nothing => putStrLn "unexpected: the channel is empty"
    putStrLn v
    -- A second put waits until the first value has been taken.
    tid <- fork $ do
        channelPut chan "first"
        channelPut chan "second"
        putStrLn "both values are sent"
    first <- channelGet chan
    putStrLn first
    second <- channelGet chan
    putStrLn second
    threadWait tid
