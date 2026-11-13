module Main

-- These functions borrow their arguments: the generated C takes no
-- reference to the lists and releases nothing.

len : List a -> Nat -> Nat
len [] acc = acc
len (_ :: xs) acc = len xs (S acc)

data Tree = Leaf | Node Tree Int Tree

sumT : Tree -> Int
sumT Leaf = 0
sumT (Node l v r) = sumT l + v + sumT r

build : Int -> Tree
build 0 = Leaf
build n = Node (build (n - 1)) n Leaf

main : IO ()
main = do
  printLn (len [1, 2, 3] 0)
  printLn (sumT (build 100))
