module Libs

import Data.IORef
import Data.List

-- Library functions that used to need a stack as deep as the list: ranges
-- (built with `takeUntil`) and `traverse_`, `for_` and `sequence_` on lists
-- in `IO` (a chain of `*>`).  The test runs them on the main thread of Node,
-- with its small stack.

main : IO ()
main = do
  let n = 1000000
  printLn (length [1 .. the Int n])
  printLn (length [the Int n, n - 1 .. 1])
  printLn (length [1, 3 .. the Integer (cast n)])
  printLn (length [1 .. the Nat (cast n)])
  printLn (length [the Nat (cast n) .. 1])
  r <- newIORef (the Int 0)
  for_ [1 .. n] $ \i => modifyIORef r (+ i `mod` 7)
  traverse_ (\i => modifyIORef r (+ i `mod` 5)) [1 .. n]
  sequence_ (replicate 100000 (modifyIORef r (+1)))
  readIORef r >>= printLn
