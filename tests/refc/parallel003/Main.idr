module Main

import Data.List
import System
import System.Concurrency

-- Producers and consumers that pass lists through channels: the values made
-- by a thread are released by another one.
producer : Channel (Maybe (List Integer)) -> Integer -> IO ()
producer chan k = for_ [1 .. 2000] $ \i =>
    channelPut chan (Just [k * i .. k * i + 20])

consumer : Channel (Maybe (List Integer)) -> Channel Integer -> IO ()
consumer chan res = go 0
  where
    go : Integer -> IO ()
    go acc = do
        v <- channelGet chan
        case v of
            Nothing => channelPut res acc
            Just xs => go (acc + sum xs)

main : IO ()
main = do
    chan <- makeChannel
    res <- makeChannel
    cs <- for [1 .. 4] $ \_ => fork (consumer chan res)
    ps <- for [1 .. 4] $ \k => fork (producer chan k)
    for_ ps $ \tid => threadWait tid
    for_ [1 .. 4] $ \_ => channelPut chan Nothing
    sums <- for [1 .. 4] $ \_ => channelGet res
    for_ cs $ \tid => threadWait tid
    printLn (sum sums)
