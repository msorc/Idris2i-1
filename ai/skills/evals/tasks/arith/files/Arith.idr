||| Arithmetic facts and size-indexed functions for the layout engine.
module Arith

import Data.Nat
import Data.Vect

%default total

||| The sum 0 + 1 + ... + n.
public export
sumTo : Nat -> Nat
sumTo Z = Z
sumTo (S k) = S k + sumTo k

||| The sum 0*0 + 1*1 + ... + n*n.
public export
sumSquares : Nat -> Nat
sumSquares Z = Z
sumSquares (S k) = S k * S k + sumSquares k

-- Facts about numbers ---------------------------------------------------------

export
binomial : (a, b : Nat) -> (a + b) * (a + b) = a * a + 2 * a * b + b * b
binomial a b = ?binomial_rhs

export
foil : (a, b, c, d : Nat) -> (a + b) * (c + d) = a * c + a * d + b * c + b * d
foil a b c d = ?foil_rhs

export
cubeStep : (n : Nat) -> (n + 1) * (n + 1) * (n + 1) = n * n * n + 3 * n * n + 3 * n + 1
cubeStep n = ?cubeStep_rhs

export
gridArea : (w, h, gap : Nat) -> (w + gap) * (h + gap) + w * h = 2 * w * h + gap * (w + h + gap)
gridArea w h gap = ?gridArea_rhs

export
gauss : (n : Nat) -> 2 * sumTo n = n * (n + 1)
gauss n = ?gauss_rhs

export
pyramid : (n : Nat) -> 6 * sumSquares n = n * (n + 1) * (2 * n + 1)
pyramid n = ?pyramid_rhs

-- Functions whose sizes need those facts ---------------------------------------

||| `interleave [a, b, c] [x, y, z] = [a, x, b, y, c, z]`
export
interleave : Vect n a -> Vect n a -> Vect (2 * n) a
interleave xs ys = ?interleave_rhs

||| Rows of a grid one after another: `flatten [[1, 2, 3], [4, 5, 6]] = [1, 2, 3, 4, 5, 6]`.
||| The size is written columns first, as the callers have it.
export
flatten : Vect rows (Vect cols a) -> Vect (cols * rows) a
flatten xss = ?flatten_rhs

||| A frame around a grid cell: the element, `pad` copies of the filler on each
||| side. `frame 2 '.' 'x' = ['.', '.', 'x', '.', '.']`
export
frame : (pad : Nat) -> a -> a -> Vect (2 * pad + 1) a
frame pad filler x = ?frame_rhs

||| The first, middle and last third: `thirds [1, 2, 3, 4, 5, 6] = ([1, 2], [3, 4], [5, 6])`.
export
thirds : {n : Nat} -> Vect (3 * n) a -> (Vect n a, Vect n a, Vect n a)
thirds xs = ?thirds_rhs
