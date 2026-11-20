-- Mandelbrot: points of the plane as records of two Doubles, iterated
-- until they escape.  Input: the size of the grid.
module Main

import Data.String

record Complex where
  constructor MkC
  re, im : Double

sq : Complex -> Complex
sq (MkC a b) = MkC (a * a - b * b) (2.0 * a * b)

add : Complex -> Complex -> Complex
add (MkC a b) (MkC c d) = MkC (a + c) (b + d)

norm2 : Complex -> Double
norm2 (MkC a b) = a * a + b * b

iter : Int -> Complex -> Complex -> Int
iter 0 _ _ = 0
iter k c z = if norm2 z > 4.0 then k else iter (k - 1) c (add (sq z) c)

row : Int -> Int -> Int -> Int -> Int
row n y x acc =
  if x >= n then acc else
    let c = MkC (cast x * 3.0 / cast n - 2.0) (cast y * 2.0 / cast n - 1.0)
    in row n y (x + 1) (acc + iter 100 c (MkC 0.0 0.0))

grid : Int -> Int -> Int -> Int
grid n y acc = if y >= n then acc else grid n (y + 1) (row n y 0 acc)

main : IO ()
main = do
  line <- getLine
  let n = cast {to = Int} (trim line)
  printLn (grid n 0 0)
