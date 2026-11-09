module Main

import System
import System.Concurrency

-- Test the non-blocking and the timed channel operations.
main : IO ()
main = do
    chan <- makeChannel
    nothing <- channelGetNonBlocking chan
    case nothing of
        Nothing => putStrLn "there is nothing to get"
        Just v => putStrLn ("unexpected value: " ++ v)
    tid <- fork $ channelPut chan "sent"
    value <- channelGet chan
    putStrLn value
    threadWait tid
    expired <- channelGetWithTimeout chan 10
    case expired of
        Nothing => putStrLn "the channel is still empty"
        Just v => putStrLn ("unexpected value: " ++ v)
    -- The timed out get must not have swallowed the next value.
    tid2 <- fork $ channelPut chan "after the timeout"
    value2 <- channelGet chan
    putStrLn value2
    threadWait tid2
