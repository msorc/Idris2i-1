module Libs

import Data.IORef
import Data.List
import Data.SortedMap
import Data.SortedSet

-- Library functions that used to need a stack as deep as the list: ranges
-- (built with `takeUntil`), `traverse_`, `for_` and `sequence_` on lists in
-- `IO` (a chain of `*>`), `traverse`, `for`, `sequence` (a chain of `<*>`)
-- and `foldlM` (of `>>=`) on lists in `IO`, `and` and `or` on lists (of
-- `&&` and `||`), and `toList` of a `SortedMap` (continuations).  The test runs them on the main thread of Node,
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
  ys <- traverse (\i => pure (i + 1)) [1 .. n]
  printLn (sum (map (\i => the Integer (cast i)) ys))
  zs <- for [1 .. n] (\i => pure (i * 2))
  printLn (length zs)
  ws <- sequence (map pure [1 .. n])
  printLn (length ws)
  foldlM (\a, b => pure (a + the Integer (cast b))) 0 [1 .. n] >>= printLn
  printLn (and (map (\i => delay (i > 0)) [1 .. n]), or (map (\i => delay (i < 0)) [1 .. n]))
  printLn (and [True, False, delay (assert_total (idris_crash "not forced"))])
  printLn (or [False, True, delay (assert_total (idris_crash "not forced"))])
  printLn (length (SortedMap.toList (SortedMap.fromList (map (\i => (i, i)) [1 .. n]))))
  printLn (length (SortedSet.toList (SortedSet.fromList [1 .. n])))
  printLn (SortedMap.toList (SortedMap.fromList [(3, "c"), (1, "a"), (2, "b")]))
