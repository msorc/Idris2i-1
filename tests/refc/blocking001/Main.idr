-- 100 green threads, each in a call that blocks its OS thread for 50ms,
-- run through idris2i_1_blockingCall on a pool of 4 threads: they take about
-- 100 * 50ms / 4, not 100 * 50ms / (the number of workers), and the other
-- threads keep running meanwhile.
import Data.IORef
import System
import System.Clock
import System.Concurrency

%foreign "C:test_sleepBlocking, libsleeper, sleeper.h"
prim__sleepBlocking : Int -> PrimIO Int

sleepBlocking : Int -> IO Int
sleepBlocking ms = primIO $ prim__sleepBlocking ms

ms : Clock Monotonic -> Integer
ms c = seconds c * 1000 + nanoseconds c `div` 1000000

main : IO ()
main = do
  start <- clockTime Monotonic
  -- before the first fork: the main thread alone
  r <- sleepBlocking 10
  putStrLn "a blocking call before the first fork: \{show r}"
  results <- makeChannel
  ts <- for [1 .. 100] $ \_ => fork $ do
    r <- sleepBlocking 50
    channelPut results r
  -- a thread that ticks meanwhile
  ticks <- newIORef (the Int 0)
  ticker <- fork $ for_ [1 .. 10] $ \_ => do
    usleep 10000
    modifyIORef ticks (+1)
  rs <- for [1 .. 100] $ \_ => channelGet results
  traverse_ (\t => threadWait t) ts
  threadWait ticker
  end <- clockTime Monotonic
  putStrLn "the calls returned: \{show (sum rs)}"
  putStrLn "ticks: \{show !(readIORef ticks)}"
  let elapsed = ms end - ms start
  putStrLn "more than 1s (100 calls of 50ms on 4 threads): \{show (elapsed >= 1250)}"
  putStrLn "less than 5s: \{show (elapsed < 5000)}"
