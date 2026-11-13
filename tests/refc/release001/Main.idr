-- Releasing values whose long spine is not in their last field (the first
-- field of a SnocList, the left branch of a tree) takes no stack: here in a
-- thread with a small stack.
import System.Concurrency
import Data.SnocList

data Tree = Leaf | Node Tree Int Tree

build : SnocList Int -> Int -> SnocList Int
build acc 0 = acc
build acc n = build (acc :< n) (n - 1)

-- a tree that leans to the left
leftDeep : Tree -> Int -> Tree
leftDeep t 0 = t
leftDeep t n = leftDeep (Node t n Leaf) (n - 1)

cnt : Nat -> SnocList Int -> Nat
cnt k [<] = k
cnt k (sx :< _) = cnt (S k) sx

depth : Nat -> Tree -> Nat
depth k Leaf = k
depth k (Node l _ _) = depth (S k) l

main : IO ()
main = do
  t <- fork $ do
    pure ()
    printLn (cnt 0 (build [<] 1000000))
    printLn (depth 0 (leftDeep Leaf 1000000))
  threadWait t
