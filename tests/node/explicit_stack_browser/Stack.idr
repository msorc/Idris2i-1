module Stack

import Data.List
import Data.List1
import Data.String
import Debug.Trace

-- Functions that call themselves where the call is not a tail call are
-- compiled to loops on an explicit stack on the JavaScript backends, so that
-- they run on long lists with the small stack of a browser (or of the main
-- thread of Node).

n : Nat
n = 100000

xs : List Int
xs = [1 .. cast n]

-- the call in an argument of an unknown function (`foldr`)
sumR : List Int -> Int
sumR = foldr (+) 0

-- the call in the scrutinee of a `case` (`span`, `unzip`, ...)
evensOdds : List Int -> (List Int, List Int)
evensOdds [] = ([], [])
evensOdds (x :: xs)
    = let (es, os) = evensOdds xs in
          if mod x 2 == 0 then (x :: es, os) else (es, x :: os)

-- two calls, the second one in the frame of the first
data Tree = Leaf | Node Tree Int Tree

size : Tree -> Nat
size Leaf = 0
size (Node l _ r) = size l + S (size r)

-- the treeInt benchmark: `build` calls itself in an argument of `insert`
insert : Int -> Tree -> Tree
insert x Leaf = Node Leaf x Leaf
insert x (Node l v r) = if x < v then Node (insert x l) v r else Node l v (insert x r)

build : List Int -> Tree
build [] = Leaf
build (x :: xs) = insert x (build xs)

-- a call in the arguments of a call
ack : Nat -> Nat -> Nat
ack Z m = S m
ack (S k) Z = ack k 1
ack (S k) (S m) = ack k (ack (S k) m)

-- a call in the value of a `let`, and a tail call
countDown : Nat -> List Nat
countDown Z = []
countDown (S k) = let rest = countDown k in if k == 50000 then countDown k else S k :: rest

-- the order of evaluation is the one without the loop
traced : List Int -> Int
traced [] = trace "end" 0
traced (x :: xs) = trace "before \{show x}" x + traced xs + trace "after \{show x}" 0

-- a call under a lambda or in a lazy value is not one of the loop
lazyRec : List Int -> Lazy Int
lazyRec [] = 0
lazyRec (x :: xs) = x + force (lazyRec xs)

main : IO ()
main = do
  printLn (sumR xs)
  printLn (foldr (\x, acc => x :: acc) [] xs == xs)
  printLn (length (fst (span (< 90000) xs)), length (snd (break (> 10) xs)))
  printLn (length (fst (splitAt 99999 xs)))
  printLn (length (fst (partition (> 5) xs)))
  printLn (length (fst (unzip (zip xs xs))))
  printLn (length (group (map (`div` 2) xs)))
  printLn (map length (traverse Just xs))
  printLn (map length (the (Either String (List Int)) (traverse Right xs)))
  printLn (foldlM (\a, b => Just (a + b)) 0 xs)
  printLn (bimap length length (evensOdds xs))
  let t = build (map (\i => mod (i * 7919) 100003) xs)
  printLn (size t)
  printLn (ack 2 3, ack 3 3)
  printLn (length (countDown n))
  printLn (traced [1, 2, 3])
  printLn (force (lazyRec [1, 2, 3]))
  ys <- traverse (\x => pure (x + 1)) xs
  printLn (length ys)
  zs <- for xs (\x => pure (x * 2))
  printLn (sum zs)
  ws <- sequence (map pure xs)
  printLn (length ws)
  s <- foldlM (\a, b => pure (a + b)) 0 xs
  printLn s
  traverse_ printLn !(traverse (\x => do printLn x; pure (x * 10)) [1, 2, 3])
  printLn !(foldlM (\a, b => do putStrLn "step \{show b}"; pure (a - b)) 100 [1, 2, 3])
