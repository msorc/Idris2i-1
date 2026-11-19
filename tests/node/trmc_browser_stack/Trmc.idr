module Trmc

import Data.List
import Data.List1
import Data.String
import Debug.Trace

-- Functions that make a cell of a call to themselves ("tail recursion modulo
-- cons") are compiled to loops on the JavaScript backends, so that they run
-- on long lists with the small stack of a browser (or of the main thread of
-- Node).

n : Nat
n = 200000

xs : List Int
xs = [1 .. cast n]

-- a cell in a cell, and a tail call to itself
pairsUp : List Int -> List Int
pairsUp (x :: y :: rest) = if x == y then pairsUp rest else x :: y :: pairsUp rest
pairsUp rest = rest

-- the hole in a record and in a constructor of a data type
record Chain where
  constructor MkChain
  val : Int
  next : Maybe Chain

chain : List Int -> Maybe Chain
chain [] = Nothing
chain (x :: xs) = Just (MkChain x (chain xs))

chainLength : Maybe Chain -> Nat -> Nat
chainLength Nothing k = k
chainLength (Just c) k = chainLength c.next (S k)

data Tree = Leaf | Node Tree Int Tree

-- two calls in a cell: the last one is the hole (here, on the deep side)
mirror : Tree -> Tree
mirror Leaf = Leaf
mirror (Node l x r) = Node (mirror r) x (mirror l)

-- (the fields after the hole must only allocate: `Node (spine k) (cast k)
-- Leaf` would not be a loop)
spine : Nat -> Tree
spine Z = Leaf
spine (S k) = Node (spine k) 1 Leaf

rightDepth : Tree -> Nat -> Nat
rightDepth Leaf k = k
rightDepth (Node _ _ r) k = rightDepth r (S k)

-- the fields are computed in the same order as without the loop
traced : List Int -> List Int
traced [] = []
traced (x :: xs) = trace "field \{show x}" x :: traced xs

-- the hole in a `case` in a field (`tails`)
suffixSums : List Int -> List Int
suffixSums xs = sum xs :: case xs of
  [] => []
  (_ :: rest) => if length rest > 3 then suffixSums rest else []

-- a lazy field is not a hole
lazyNats : Int -> Stream Int
lazyNats k = k :: lazyNats (k + 1)

main : IO ()
main = do
  printLn (length (zipWith (+) xs xs))
  printLn (length (zip xs xs))
  printLn (length (take 150000 xs))
  printLn (length (intersperse 0 xs))
  printLn (length (deleteBy (==) (cast n) xs))
  printLn (length (iterateN n (+1) (the Int 0)))
  printLn (length (map (* 2) (sort (reverse xs))))
  printLn (length (pairsUp (concatMap (\x => [x, x + 1]) xs)))
  printLn (pairsUp [1, 1, 2, 3, 4, 4, 5])
  printLn (chainLength (chain xs) 0)
  printLn (rightDepth (mirror (spine n)) 0)
  printLn (traced [1, 2, 3])
  printLn (take 3 (lazyNats 7))
  printLn (length (tails xs))
  printLn (suffixSums [1, 2, 3, 4, 5, 6])
