||| A flat array that two threads read and write (its slots are copied under
||| its lock when it is shared).  Each thread updates every other element (a
||| read then a write, which are not atomic together: on the same elements
||| the threads could lose each other's updates), all of them in the same
||| array at the same time.
module Threads

import Data.IOArray
import System.Concurrency

record P where
  constructor MkP
  x : Double
  n : Int

main : IO ()
main = do
  a <- newArray {elem = P} 1000
  for_ [0 .. 999] $ \i => ignore (writeArray a i (MkP (cast i) i))
  t <- fork $ for_ [0, 2 .. 998] $ \i => do
         Just p <- readArray a i | Nothing => pure ()
         ignore (writeArray a i ({ x $= (+ 2.0) } p))
  for_ [1, 3 .. 999] $ \i => do
    Just p <- readArray a i | Nothing => pure ()
    ignore (writeArray a i ({ n $= (+ 2) } p))
  threadWait t
  ps <- toList a
  printLn (foldl (\s, m => maybe s (\p => s + p.x + cast p.n) m) 0.0 ps)
