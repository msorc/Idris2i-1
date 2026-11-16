-- Closures that hold no argument and constructors whose fields are all
-- static are data of the C program (IDRIS2_STATIC_CLOSURE,
-- IDRIS2_STATIC_CONSTRUCTOR): nothing is allocated for them, they are
-- never released, and applying them does not write to them.
import Data.List

data Op = MkOp (Int -> Int) (Int -> Int -> Int) String

%noinline
run : Op -> Int -> Int
run (MkOp f g _) x = g (f x) x

-- a static constructor of two static closures and a string
%noinline
op : Int -> Op
op n = MkOp (\x => x + 1) (\a, b => a * b) "op"

loop : Int -> Int -> Int
loop 0 acc = acc
loop n acc = loop (n - 1) ((acc + run (op n) n) `mod` 1000003)

-- a static constructor inside a static constructor
%noinline
nested : Int -> (Op, Maybe Op, List Bool)
nested n = (MkOp (\x => x * 2) (\a, b => a - b) "a", Just (MkOp (\x => x) (\a, b => b) "b"), [True, False])

%noinline
three : Int -> Int -> Int -> Int
three a b c = a * 100 + b * 10 + c

interface Shape a where
  area : a -> Int
  name : a -> String

Shape Int where
  area x = x * x
  name _ = "square"

%noinline
describe : Shape a => a -> String
describe x = name x ++ " " ++ show (area x)

main : IO ()
main = do
  printLn (loop 100000 0)
  let (a, mb, bs) = nested 1
  printLn (run a 5, map (\o => run o 5) mb, bs)
  -- a static closure applied to one argument at a time, and to several
  let fs = map three [1, 2]
  printLn (map (\f => f 3 4) fs)
  let gs = map (\f => f 5) fs
  printLn (map (\g => g 6) gs, map (\g => g 7) gs)
  -- the same static closure, applied many times
  printLn (foldl (\acc, f => f acc 1 2) 0 (replicate 5 three))
  printLn (sortBy (\x, y => compare y x) [3, 1, 2])
  putStrLn (describe (the Int 7))
