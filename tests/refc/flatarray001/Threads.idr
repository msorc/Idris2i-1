||| A flat array that two threads read and write (its slots are copied under
||| its lock when it is shared).
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
  t <- fork $ for_ [0 .. 999] $ \i => do
         Just p <- readArray a i | Nothing => pure ()
         ignore (writeArray a i ({ x $= (+ 1.0) } p))
  for_ [0 .. 999] $ \i => do
    Just p <- readArray a i | Nothing => pure ()
    ignore (writeArray a i ({ n $= (+ 1) } p))
  threadWait t
  ps <- toList a
  printLn (foldl (\s, m => maybe s (\p => s + p.x + cast p.n) m) 0.0 ps)
