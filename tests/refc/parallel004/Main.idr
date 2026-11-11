module Main

import Data.IORef
import Data.List
import System
import System.Concurrency

-- Threads that read the same data in parallel: a list built before the
-- threads start, a top level constant, and an IORef that another thread
-- keeps replacing.  Their reference counts change in parallel.
shared : List Integer
shared = [1 .. 3000]

main : IO ()
main = do
    let local = map (* 2) [1 .. 3000]
    ref <- newIORef local
    done <- makeChannel
    writer <- fork $ for_ [1 .. 300] $ \i => writeIORef ref (map (+ i) local)
    tids <- for [1 .. 6] $ \_ => fork $ do
        for_ [1 .. 300] $ \_ => do
            xs <- readIORef ref
            let s = sum xs + sum local + sum shared
            if s > 0 then pure () else putStrLn "unexpected"
        channelPut done (sum local + sum shared)
    rs <- for [1 .. 6] $ \_ => channelGet done
    for_ tids $ \tid => threadWait tid
    threadWait writer
    printLn (sum rs)
    xs <- readIORef ref
    printLn (sum xs)
