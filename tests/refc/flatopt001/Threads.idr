||| A flat array that two threads read and write through the flat accesses
||| (shared, its slots are read and written through values, under its lock),
||| and one of the layout of values read through them.
module Threads

import Data.IOArray
import System.Concurrency

record P where
  constructor MkP
  x : Double
  n : Int

-- (every other element: the threads write different ones)
bump : IOArray P -> Int -> Int -> IO ()
bump a k i =
  if i >= k then pure () else do
    Just p <- readFlatArray a i | Nothing => bump a k (i + 2)
    ignore (writeFlatArray a i (MkP (p.x + 1.0) (p.n + 2)))
    bump a k (i + 2)

total' : IOArray P -> Int -> Int -> Double -> IO Double
total' a k i s =
  if i >= k then pure s else do
    Just p <- readFlatArray a i | Nothing => total' a k (i + 1) s
    total' a k (i + 1) (s + p.x + cast p.n)

main : IO ()
main = do
  a <- newFlatArray {elem = P} 1000
  for_ [0 .. 999] $ \i => ignore (writeFlatArray a i (MkP (cast i) i))
  t <- fork (bump a 1000 0)
  bump a 1000 1
  threadWait t
  printLn !(total' a 1000 0 0.0)
  -- (made with the layout of values)
  b <- newArray {elem = P} 10
  for_ [0 .. 9] $ \i => ignore (writeArray b i (MkP (cast i) i))
  bump b 10 0
  bump b 10 1
  printLn !(total' b 10 0 0.0)
