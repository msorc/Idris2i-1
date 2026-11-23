import Data.Nat.Solver
import Data.Nat

%default total

failing "solveNat: the two sides are not equal as polynomials:\n  x + y\n  x * y"
  notEqual : (x, y : Nat) -> x + y = x * y
  notEqual x y = solveNat

-- True in Nat because of truncated subtraction, but `minus` is an atom
failing "the two sides are not equal as polynomials"
  truncated : (x : Nat) -> minus x (x + 1) = 0
  truncated x = solveNat

-- Only equalities are goals
failing "solveNat: the goal is not an equality of natural numbers: LTE x (x + 1)"
  notAnEquality : (x : Nat) -> LTE x (x + 1)
  notAnEquality x = solveNat

-- Only natural numbers
failing "solveNat: the goal is not an equality of natural numbers"
  integers : (x, y : Integer) -> x + y = y + x
  integers x y = solveNat

-- Atoms are compared syntactically: their arguments are not solved
failing "the two sides are not equal as polynomials:\n  (f (plus x y))\n  (f (plus y x))"
  underAtom : (f : Nat -> Nat) -> (x, y : Nat) -> f (x + y) = f (y + x)
  underAtom f x y = solveNat
