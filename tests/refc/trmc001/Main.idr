-- Tail recursion modulo cons: functions that make a cell of a call to
-- themselves loop instead of recursing, so they work on long lists in a
-- thread with a small stack (see run).
import Data.List
import System.Concurrency

myMap : (a -> b) -> List a -> List b
myMap f [] = []
myMap f (x :: xs) = f x :: myMap f xs

append : List a -> List a -> List a
append [] ys = ys
append (x :: xs) ys = x :: append xs ys

-- some branches are calls to itself in tail position, others cells
myFilter : (a -> Bool) -> List a -> List a
myFilter p [] = []
myFilter p (x :: xs) = if p x then x :: myFilter p xs else myFilter p xs

-- Int parameters (C integers)
upto : Int -> Int -> List Int
upto i n = if i > n then [] else i :: upto (i + 1) n

-- the cell goes in another field than the last, and a base case that is
-- not a constant
myTake : Nat -> List a -> List a
myTake Z xs = []
myTake (S k) [] = []
myTake (S k) (x :: xs) = x :: myTake k xs

data Tree = Leaf | Node Tree Int Tree

-- the call is the first field
leftSpine : Int -> Tree
leftSpine 0 = Leaf
leftSpine n = Node (leftSpine (n - 1)) n Leaf

depth : Nat -> Tree -> Nat
depth acc Leaf = acc
depth acc (Node l _ _) = depth (S acc) l

-- a parameter that it only looks at (borrowed)
addLen : List Int -> List Int -> List Int
addLen ref [] = []
addLen ref (x :: xs) = (x + cast (length ref)) :: addLen ref xs

total' : List Int -> Int
total' = foldl (+) 0

main : IO ()
main = do
  t <- fork $ do
    pure ()
    let n = 1000000
    let xs = upto 1 n
    printLn (total' xs)
    printLn (total' (myMap (* 2) xs))
    printLn (length (append xs xs))
    printLn (total' (myFilter (\x => x `mod` 3 == 0) xs))
    printLn (total' (myTake 500000 xs))
    -- (released without a deep stack too, see idris2_releaseValue)
    printLn (depth 0 (leftSpine 1000000))
    printLn (total' (addLen [1, 2, 3] xs))
    -- used as a closure
    printLn (map (total' . myMap (+ 1)) [[1, 2], [3]])
  threadWait t
