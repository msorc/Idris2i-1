module Check

import Data.Nat
import Data.Vect
import Arith

%default total

-- The statements as given: this file checks only when Arith proves exactly these,
-- with total definitions.
c1 : (a, b : Nat) -> (a + b) * (a + b) = a * a + 2 * a * b + b * b
c1 = binomial

c2 : (a, b, c, d : Nat) -> (a + b) * (c + d) = a * c + a * d + b * c + b * d
c2 = foil

c3 : (n : Nat) -> (n + 1) * (n + 1) * (n + 1) = n * n * n + 3 * n * n + 3 * n + 1
c3 = cubeStep

c4 : (w, h, gap : Nat) -> (w + gap) * (h + gap) + w * h = 2 * w * h + gap * (w + h + gap)
c4 = gridArea

c5 : (n : Nat) -> 2 * sumTo n = n * (n + 1)
c5 = gauss

c6 : (n : Nat) -> 6 * sumSquares n = n * (n + 1) * (2 * n + 1)
c6 = pyramid

f1 : Vect n a -> Vect n a -> Vect (2 * n) a
f1 = interleave

f2 : Vect rows (Vect cols a) -> Vect (cols * rows) a
f2 = flatten

f3 : (pad : Nat) -> a -> a -> Vect (2 * pad + 1) a
f3 = frame

f4 : {n : Nat} -> Vect (3 * n) a -> (Vect n a, Vect n a, Vect n a)
f4 = thirds

main : IO ()
main = do
  printLn (f1 [1, 2, 3] (the (Vect 3 Int) [10, 20, 30]))
  printLn (f1 [] (the (Vect 0 Int) []))
  printLn (f1 ["a", "b", "c", "d", "e"] ["v", "w", "x", "y", "z"])
  printLn (f2 (the (Vect 2 (Vect 3 Int)) [[1, 2, 3], [4, 5, 6]]))
  printLn (f2 (the (Vect 3 (Vect 2 Int)) [[1, 2], [3, 4], [5, 6]]))
  printLn (f2 (the (Vect 0 (Vect 4 Int)) []))
  printLn (f2 (the (Vect 3 (Vect 1 Char)) [['p'], ['q'], ['r']]))
  printLn (f3 2 '.' 'x')
  printLn (f3 0 '.' 'x')
  printLn (f3 4 0 (the Int 7))
  printLn (f4 {n = 2} (the (Vect 6 Int) [1, 2, 3, 4, 5, 6]))
  printLn (f4 {n = 0} (the (Vect 0 Int) []))
  printLn (f4 {n = 3} (the (Vect 9 Char) ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i']))
