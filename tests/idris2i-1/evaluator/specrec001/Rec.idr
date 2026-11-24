module Rec

-- The copies of these `%spec` functions call themselves (and the copies of
-- their case blocks and local functions), not the generic functions, which
-- take the implementation of `Eq` at run time.

-- The recursive calls are under a case block whose environment has a
-- variable with the name of an argument of the type, `k` (the type `k` of
-- the type is `{k:...}` in the clause), as in `insertAt` of Data.HashMap.
%spec eq
countK : {auto eq : Eq k} -> (0 n : Nat) -> k -> List k -> Nat
countK n k [] = 0
countK n k (k' :: ks) = case k == k' of
  True => S (countK (S n) k ks)
  False => countK n k ks

-- The recursion is in a local function.
%spec eq
countW : {auto eq : Eq a} -> a -> List a -> Nat
countW x xs = go xs
  where
    go : List a -> Nat
    go [] = 0
    go (y :: ys) = if x == y then S (go ys) else go ys

-- A local function calls the function again.
%spec eq
countL : {auto eq : Eq a} -> a -> List a -> Nat
countL x [] = 0
countL x (y :: ys) = step ys
  where
    step : List a -> Nat
    step zs = if x == y then S (countL x zs) else countL x zs

-- A function with `%spec` by an interface that has `Eq` as its parent
-- calls them, as `insert` of Data.HashMap calls `insertAt`.
interface Eq a => Key a where
  key : a -> Int

Key Int where
  key x = x

%spec h
countAll : {auto h : Key a} -> a -> List a -> List Nat
countAll x xs = [countK Z x xs, countW x xs, countL x xs]

main : IO ()
main = printLn (countAll (the Int 3) [1, 3, 3, 4, 3])
