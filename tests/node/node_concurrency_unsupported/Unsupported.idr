module Unsupported

-- What no single thread can do stops the program with a message, whatever
-- the thread does next.

import System
import System.Concurrency
import System.Future

after : IO ()
after = putStrLn "not reached"

run : String -> IO ()
run "fork" = do
  _ <- fork (putStrLn "child")
  after
run "future" = do
  let f = fork (the Int (6 * 7))
  printLn (await f)
  after
run "forkIO" = do
  f <- forkIO (putStrLn "child")
  printLn (await f)
  after
run "channelGet" = do
  c <- makeChannel {a = Int}
  _ <- channelGet c
  after
run "channelPut" = do
  c <- makeChannel
  channelPut c (the Int 1)
  channelPut c 2
  after
run "semaphore" = do
  s <- makeSemaphore 1
  semaphoreWait s
  semaphoreWait s
  after
run "condition" = do
  m <- makeMutex
  c <- makeCondition
  mutexAcquire m
  conditionWait c m
  after
run "barrier" = do
  b <- makeBarrier 2
  barrierWait b
  after
run "release" = do
  m <- makeMutex
  mutexRelease m
  after
run _ = putStrLn "unknown"

main : IO ()
main = do
  [_, which] <- getArgs
    | _ => putStrLn "usage"
  putStrLn ("run " ++ which)
  run which
