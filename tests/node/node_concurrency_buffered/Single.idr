module Single

-- Buffered channels and atomic IORef operations in a program that has one
-- thread, as on Node: a put on a full channel stops the program, as nothing
-- else could take a value out of it.

import Data.IORef
import System
import System.Concurrency

main : IO ()
main = do
    c <- makeBufferedChannel 3
    for_ [1 .. 3] $ \i => channelPut c (the Int i)
    xs <- for [1 .. 3] $ \_ => channelGet c
    printLn xs
    channelGetNonBlocking c >>= printLn
    channelGetWithTimeout c 20 >>= printLn
    u <- makeUnboundedChannel
    for_ [1 .. 100] $ \i => channelPut u (the Int i)
    ys <- for [1 .. 100] $ \_ => channelGet u
    printLn (ys == [1 .. 100])

    r <- newIORef (the (List Int) [1, 2])
    t <- readForCAS r
    casIORef r t [3] >>= printLn
    casIORef r t [4] >>= printLn
    t <- readForCAS r
    writeIORef r (reverse (reverse (peekTicket t)))
    casIORef r t [5] >>= printLn
    n <- newIORef (the Int 0)
    for_ [1 .. 10] $ \_ => atomicModifyIORef_ n (+ 1)
    old <- atomicModifyIORef n (\x => (x * 2, x))
    printLn (old, !(readIORef n))

    for_ [1 .. 3] $ \i => channelPut c i
    putStrLn "the channel is full"
    channelPut c 4
    putStrLn "not reached"
