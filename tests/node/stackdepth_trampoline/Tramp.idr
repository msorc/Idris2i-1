module Tramp

import Data.IORef
import Data.List
import Data.Maybe

-- Tail calls to functions that are not known statically: before the
-- trampoline, each of these loops nested a JavaScript call per iteration and
-- overflowed the stack of Node's main thread at 2000 to 10000 iterations.

-- a `do` block in `Maybe`
countMaybe : Int -> Int -> Maybe Int
countMaybe acc 0 = Just acc
countMaybe acc n = do
  x <- Just (acc + 1)
  countMaybe x (n - 1)

-- through an unknown monad
countM : Monad m => Int -> Int -> m Int
countM acc 0 = pure acc
countM acc n = do
  x <- pure (acc + 1)
  countM x (n - 1)

-- continuation-passing style
sumCPS : List Int -> (Int -> r) -> r
sumCPS [] k = k 0
sumCPS (x :: xs) k = sumCPS xs (\s => k (s + x))

-- foreign code calling back into Idris: the callback's own loop must run to
-- the end before the foreign function uses its result
%foreign "javascript:lambda:(f, x) => f(x) + 1"
prim__applyPlusOne : (Int -> Int) -> Int -> Int

%foreign "javascript:lambda:(act, w) => { act(w); act(w) }"
prim__twice : PrimIO () -> PrimIO ()

main : IO ()
main = do
  let n = 1000000
  printLn (countMaybe 0 n)
  printLn (countM {m = Maybe} 0 n)
  printLn (countM {m = Either String} 0 n)
  r <- countM {m = IO} 0 n
  printLn r
  sumCPS (replicate 300000 1) printLn
  printLn (prim__applyPlusOne (\x => fromMaybe 0 (countMaybe x n)) 5)
  ref <- newIORef (the Int 0)
  primIO $ prim__twice $ toPrim $ do
    v <- countM {m = IO} 0 100000
    modifyIORef ref (+ v)
  readIORef ref >>= printLn
