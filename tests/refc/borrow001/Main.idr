module Main

import Data.IORef
import Data.List

-- Walks its list without owning it (a borrowed parameter).
len : List a -> Nat
len [] = Z
len (_ :: xs) = S (len xs)

-- Used directly and as a closure: a function used as a closure owns its
-- parameters.
total' : List Int -> Int
total' [] = 0
total' (x :: xs) = x + total' xs

-- The fields of a borrowed value, stored in a new value after a case.
splitHead : List String -> Maybe (String, List String)
splitHead [] = Nothing
splitHead (x :: xs) = Just (x, xs)

-- Mutual recursion on a borrowed list.
mutual
  evens : List Int -> List Int
  evens [] = []
  evens (x :: xs) = x :: odds xs

  odds : List Int -> List Int
  odds [] = []
  odds (_ :: xs) = evens xs

-- A borrowed parameter stored in an IORef (which takes a reference).
remember : IORef (List String) -> List String -> IO ()
remember ref xs = writeIORef ref xs

-- A borrowed parameter passed on to owned and borrowed parameters at once.
both : List String -> (Nat, List String)
both xs = (len xs, xs)

-- A lambda that calls a borrowing function in tail position.
lens : List (List Int) -> List Nat
lens = map (\l => len l)

main : IO ()
main = do
  let xs = map show [1 .. the Int 10]
  printLn (len xs)
  let ys = [1 .. the Int 100]
  printLn (total' ys, map total' [[1, 2], [3, 4, 5], []])
  printLn (splitHead xs)
  printLn (splitHead (drop 9 xs))
  printLn (splitHead [])
  printLn (evens [1 .. 9], odds [1 .. 9])
  ref <- newIORef []
  remember ref (map (++ "!") xs)
  zs <- readIORef ref
  printLn zs
  printLn (both (map (++ "?") (take 3 xs)))
  printLn (lens [[1, 2, 3], [], [4]])
