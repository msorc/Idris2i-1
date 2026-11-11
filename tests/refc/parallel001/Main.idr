module Main

import System
import System.Concurrency

-- Threads that compute in parallel, each with its own data, and send their
-- results through a channel.  The work is done inside the action: an
-- argument of channelPut would be evaluated before the fork.
collatz : Int -> Int
collatz n = go n 0
  where
    go : Int -> Int -> Int
    go 1 acc = acc
    go x acc = go (if x `mod` 2 == 0 then x `div` 2 else 3 * x + 1) (acc + 1)

chunk : Int -> Int -> Int
chunk lo hi = go lo 0
  where
    go : Int -> Int -> Int
    go i acc = if i >= hi then acc else go (i + 1) (acc + collatz i)

main : IO ()
main = do
    res <- makeChannel
    let n = 200000
    let t = 8
    tids <- for [0 .. t - 1] $ \i =>
        fork $ do
            pure ()
            channelPut res (chunk (1 + i * n `div` t) (1 + (i + 1) * n `div` t))
    rs <- for [1 .. t] $ \_ => channelGet res
    for_ tids $ \tid => threadWait tid
    printLn (sum rs)
    printLn (chunk 1 (n + 1))
