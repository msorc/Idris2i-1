module Main

import Data.IORef
import System
import System.Concurrency

-- Wait until the IORef holds `n`, for five seconds at most.
waitFor : IORef Int -> Int -> IO Bool
waitFor ref n = go 500
  where
    go : Nat -> IO Bool
    go 0 = pure False
    go (S k) = do
        v <- readIORef ref
        if v == n then pure True else do usleep 10000; go k

-- The values come out in the order in which they were put.
fifo : IO ()
fifo = do
    c <- makeBufferedChannel 5
    for_ [1 .. 5] $ \i => channelPut c (the Int i)
    xs <- for [1 .. 5] $ \_ => channelGet c
    printLn xs
    channelGetNonBlocking c >>= printLn
    u <- makeUnboundedChannel
    for_ [1 .. 1000] $ \i => channelPut u (the Int i)
    ys <- for [1 .. 1000] $ \_ => channelGet u
    printLn (ys == [1 .. 1000])
    -- values that some back ends represent specially (NULL, '())
    l <- makeBufferedChannel 3
    channelPut l []
    channelPut l [the Int 1]
    channelPut l []
    channelGetNonBlocking l >>= printLn
    channelGetWithTimeout l 10 >>= printLn
    channelGet l >>= printLn
    m <- makeChannel
    channelPut m (the (Maybe Int) Nothing)
    channelGetNonBlocking m >>= printLn

-- A putter waits when the channel holds `capacity` values, and goes on
-- when one is taken.
capacity : IO ()
capacity = do
    c <- makeBufferedChannel 3
    done <- newIORef 0
    tid <- fork $ for_ [1 .. 4] $ \i => do
        channelPut c (the Int i)
        atomicModifyIORef_ done (+ 1)
    three <- waitFor done 3
    usleep 100000
    n <- readIORef done
    putStrLn "puts done before a get: \{show (three, n)}"
    x <- channelGet c
    four <- waitFor done 4
    putStrLn "got \{show x}, then all puts done: \{show four}"
    xs <- for [1 .. 3] $ \_ => channelGet c
    printLn xs
    threadWait tid

-- Producers and consumers through a small channel: every value is got once.
producer : Channel Int -> Int -> Int -> IO ()
producer c i m = for_ [1 .. m] $ \k => channelPut c (i * m + k)

consumer : Channel Int -> Channel Integer -> Int -> IO ()
consumer c results m = go m 0
  where
    go : Int -> Integer -> IO ()
    go 0 acc = channelPut results acc
    go k acc = do
        x <- channelGet c
        go (k - 1) (acc + cast x)

manyToMany : IO ()
manyToMany = do
    let p = 4
    let m = 10000
    c <- makeBufferedChannel 16
    results <- makeChannel
    ps <- for [0 .. p - 1] $ \i => fork (producer c i m)
    cs <- for [1 .. p] $ \_ => fork (consumer c results m)
    sums <- for [1 .. p] $ \_ => channelGet results
    for_ ps (\t => threadWait t)
    for_ cs (\t => threadWait t)
    let n = cast {to = Integer} (p * m)
    putStrLn "checksum: \{show (sum sums == n * (n + 1) `div` 2)}"

-- A get with a timeout gives up when nothing comes, and is woken up by a
-- put from another thread.
timeouts : IO ()
timeouts = do
    c <- makeBufferedChannel 2
    channelGetWithTimeout c 50 >>= printLn
    channelPut c (the Int 7)
    channelGetWithTimeout c 50 >>= printLn
    tid <- fork $ do usleep 50000; channelPut c 9
    channelGetWithTimeout c 10000 >>= printLn
    threadWait tid

main : IO ()
main = do
    fifo
    capacity
    manyToMany
    timeouts
