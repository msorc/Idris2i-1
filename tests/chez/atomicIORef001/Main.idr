module Main

import Data.IORef
import System
import System.Concurrency

-- What casIORef does on one thread.
casChecks : IO ()
casChecks = do
    r <- newIORef (the (List Int) [1, 2, 3])
    t <- readForCAS r
    putStrLn "ticket: \{show (peekTicket t)}"
    ok <- casIORef r t [4]
    putStrLn "swap with a fresh ticket: \{show ok}"
    ok <- casIORef r t [5]
    putStrLn "swap with a stale ticket: \{show ok}"
    t <- readForCAS r
    writeIORef r (peekTicket t)
    ok <- casIORef r t [6]
    putStrLn "swap after the same value was written back: \{show ok}"
    t <- readForCAS r
    writeIORef r (reverse (reverse (peekTicket t)))
    ok <- casIORef r t [7]
    putStrLn "swap after an equal value was built again: \{show ok}"
    readIORef r >>= printLn
    old <- atomicModifyIORef r (\xs => (8 :: xs, length xs))
    putStrLn "atomicModifyIORef gave \{show old}"
    readIORef r >>= printLn

-- `n` threads each add one to a counter `m` times, push their number on a
-- list `m` times, and sum the values that they saw before their additions:
-- with no update lost, the counter ends at n * m, the list has n * m
-- elements, and the values seen are 0 to n * m - 1, each once.
worker : IORef Int -> IORef (List Int) -> Channel Integer -> Int -> Int -> IO ()
worker counter list results i m = go m 0
  where
    go : Int -> Integer -> IO ()
    go 0 seen = channelPut results seen
    go k seen = do
        old <- atomicModifyIORef counter (\x => (x + 1, x))
        atomicModifyIORef_ list (i ::)
        go (k - 1) (seen + cast old)

main : IO ()
main = do
    casChecks
    let n = 8
    let m = 20000
    counter <- newIORef 0
    list <- newIORef []
    results <- makeChannel
    tids <- for [0 .. n - 1] $ \i => fork (worker counter list results i m)
    seen <- for [1 .. n] $ \_ => channelGet results
    for_ tids (\t => threadWait t)
    final <- readIORef counter
    xs <- readIORef list
    let nm = cast {to = Integer} (n * m)
    putStrLn "counter: \{show final} (expected \{show (n * m)})"
    putStrLn "list: \{show (length xs)} elements, sum \{show (sum xs)} (expected \{show (m * sum [0 .. n - 1])})"
    putStrLn "values seen: \{show (sum seen == nm * (nm - 1) `div` 2)}"
