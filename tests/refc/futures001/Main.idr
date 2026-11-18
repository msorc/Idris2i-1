module Main

import Data.IORef
import Data.List
import System.Concurrency
import System.Future

sumTo : Integer -> Integer -> Integer
sumTo acc 0 = acc
sumTo acc n = sumTo (acc + n) (n - 1)

-- A value with several levels, made in the thread of the future.
table : Nat -> List (Nat, String)
table n = map (\k => (k, show (k * k))) [1 .. n]

topLevel : Lazy String
topLevel = "top-level indeed"

-- Awaited by several threads at once.
reader : Future Integer -> Channel Integer -> IO ()
reader fut ch = do pure ()
                   channelPut ch (await fut + 1)

main : IO ()
main = do
  -- A constant, and a constant of the program.
  putStrLn (await (fork "String"))
  putStrLn (await (fork topLevel))

  -- `await` gives the value as many times as it is asked for.
  let f = fork (sumTo 0 100000)
  printLn (await f)
  printLn (await f + await f)

  -- Many futures at once.
  let fs = map (\n => fork (sumTo 0 (cast n * 1000))) [1 .. the Nat 50]
  printLn (sum (map await fs))

  -- A value that is not a number comes back from the thread.
  let t = fork (table 5)
  printLn (await t)
  printLn (length (await t))

  -- Functor, Applicative and Monad.
  printLn (await (map (+ 1) f))
  printLn (await [| f + pure 2 |])
  printLn (await (f >>= \x => fork (x * 2)))
  printLn (await (join (fork (fork "nested"))))
  printLn (await (do x <- fork (the Integer 3)
                     y <- map (* 2) (pure x)
                     pure (x + y)))

  -- A future of a function, and a unit.
  let g = fork (\x : Integer => x * 10)
  printLn (await (g <*> fork 4))
  printLn (await (fork ()))

  -- IO actions: the effects of the action are the ones of its thread.
  ref <- newIORef (the Integer 0)
  done <- forkIO (do modifyIORef ref (+ 5)
                     readIORef ref)
  printLn (await done)
  printLn !(readIORef ref)
  -- The action runs in a thread of its own.
  here <- getThreadId
  there <- forkIO getThreadId
  printLn (here == 0, await there /= here)
  -- Each one waits for the one before, so the lines come in order.
  first <- forkIO (putStrLn "first")
  second <- forkIO (do pure (await first); putStrLn "second")
  third <- forkIO (do pure (await second); putStrLn "third"; pure "fourth")
  putStrLn (await third)
  -- An action is a value like another: it only runs once it is given back.
  let action = await (fork (putStrLn "This is printed by the main thread"))
  action
  ran <- performFutureIO (fork (putStrLn "This is printed" >> pure 'x'))
  printLn (await ran)

  -- A future that other threads wait for.
  ch <- makeChannel
  let slow = fork (sumTo 0 300000)
  ts <- for [1 .. the Nat 4] $ \_ => fork (reader slow ch)
  vs <- for ts $ \_ => channelGet ch
  for_ ts (\t => threadWait t)
  printLn vs
