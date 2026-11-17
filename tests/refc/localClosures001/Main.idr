module Main

-- A partial application that is bound to a variable and applied once is a
-- call where it is applied (see Compiler.RefC.LocalClosures); one that is
-- used otherwise is a closure.  Each function gives what it gives without
-- that rewrite.

%noinline
f3 : Int -> Int -> Int -> Int
f3 a b c = a * 100 + b * 10 + c

%noinline
f5 : String -> String -> String -> String -> String -> String
f5 a b c d e = a ++ b ++ c ++ d ++ e

-- takes two arguments, and gives a function
%noinline
adder : Int -> Int -> (Int -> Int)
adder a b = \c => a + b + c

-- applied in one branch only
%noinline
oneBranch : Bool -> Int -> Int
oneBranch b x
    = let g = f3 x 1 in
          if b then g 7 else x

-- applied in each branch, to other arguments
%noinline
eachBranch : Nat -> Int -> Int
eachBranch n x
    = let g = f3 x 2 in
          case n of
               Z => g 0
               S Z => g 1
               _ => x

-- applied to all of its missing arguments, one at a time
%noinline
manyMissing : Bool -> String -> String
manyMissing b s
    = let g = f5 s in
          if b then g "b" "c" "d" "e" else s

-- applied to some of its missing arguments: still a partial application,
-- which escapes
%noinline
someMissing : String -> (String -> String)
someMissing s
    = let g = f5 s "-" in
          g "+" "*"

-- over-applied: the call gives a function, which is applied
%noinline
overApplied : Int -> Int
overApplied x
    = let g = adder x in
          g 10 100

-- applied twice: a closure
%noinline
twice : Int -> Int
twice x
    = let g = f3 x 3 in
          g 1 + g 2

-- applied and escaping: a closure
%noinline
escaping : Int -> (Int, Int -> Int)
escaping x
    = let g = f3 x 4 in
          (g 5, g)

-- captured by another closure
%noinline
captured : Int -> (Int -> Int)
captured x
    = let g = f3 x 5 in
          \y => g y + 1

-- stored in a list, then applied
%noinline
stored : Int -> List (Int -> Int)
stored x
    = let g = f3 x 6 in
          [g, \y => g (y + 1)]

-- the argument of a partial application that is applied once
%noinline
nested : Bool -> Int -> Int
nested b x
    = let g = f3 x 7
          h = adder x 1 in
          if b then g (h 1) else 0

-- applied to itself, in a way
%noinline
selfApplied : (Int -> Int) -> Int -> Int
selfApplied k x
    = let g = f3 x 8 in
          k (g (k (g 1)))

-- the list is matched on in the branches: its cell can be used again for
-- the result in the branch where the closure is not applied
%noinline
ins : List Int -> Int -> Int -> List Int
ins xs a b = a :: b :: xs

reuseBranch : List Int -> List Int
reuseBranch xs
    = let g = ins xs 1 in
          case xs of
               [] => g 0
               (y :: ys) => y + 1 :: ys

data T = Leaf | Node T Int T

%noinline
sizeT : T -> Int -> Int
sizeT Leaf acc = acc
sizeT (Node l v r) acc = sizeT l (sizeT r (acc + v))

-- applied in a nested branch, where the fields of what it captured are used
tree : T -> Bool -> Int
tree t b
    = let g = sizeT t in
          case t of
               Leaf => 0
               Node l _ _ => if b then g 100 else sizeT l 0

%noinline
lazyArg : Lazy Int -> Int -> Int
lazyArg x y = x + y

-- it captures a lazy argument
lazyClosure : Bool -> Int -> Int
lazyClosure b n
    = let g = lazyArg (n * 2) in
          if b then g 1 else 0

%noinline
io3 : String -> String -> IO ()
io3 a b = putStrLn (a ++ b)

-- an IO action, applied once (and run)
ioBranch : Bool -> String -> IO ()
ioBranch b s
    = let act = io3 s in
          if b then act "!" else pure ()

main : IO ()
main = do
  printLn (oneBranch True 4, oneBranch False 4)
  printLn (eachBranch 0 5, eachBranch 1 5, eachBranch 2 5)
  putStrLn (manyMissing True "a")
  putStrLn (manyMissing False "a")
  putStrLn (someMissing "x" "/")
  printLn (overApplied 1)
  printLn (twice 6)
  let (v, k) = escaping 7
  printLn (v, k 8, k 9)
  printLn (captured 1 2)
  printLn (map (\k => k 3) (stored 2))
  printLn (nested True 3, nested False 3)
  printLn (selfApplied (* 2) 9)
  printLn (reuseBranch [], reuseBranch [5, 6])
  let t = Node (Node Leaf 1 Leaf) 2 (Node Leaf 3 Leaf)
  printLn (tree t True, tree t False, tree Leaf True)
  printLn (lazyClosure True 4, lazyClosure False 4)
  ioBranch True "hey"
  ioBranch False "no"
