import Data.Nat.Solver
import Data.Vect

%default total

-- Commutativity and associativity, with 3 to 6 variables
comm2 : (x, y : Nat) -> x + y = y + x
comm2 x y = solveNat

assoc3 : (x, y, z : Nat) -> (x + y) + z = x + (y + z)
assoc3 x y z = solveNat

shuffle6 : (a, b, c, d, e, f : Nat) ->
           a + (b + (c + (d + (e + f)))) = ((f + d) + (b + e)) + (c + a)
shuffle6 a b c d e f = solveNat

multShuffle4 : (a, b, c, d : Nat) -> a * (b * (c * d)) = (d * b) * (c * a)
multShuffle4 a b c d = solveNat

-- Distributivity
distrib4 : (a, b, c, d : Nat) -> (a + b) * (c + d) = a * c + b * d + d * a + c * b
distrib4 a b c d = solveNat

square : (x, y : Nat) -> (x + y) * (x + y) = x * x + 2 * x * y + y * y
square x y = solveNat

-- Literals and S
lits : (x : Nat) -> S (S x) * 2 = 4 + x + x
lits x = solveNat

succs : (x, y : Nat) -> S x + S y = S (S (y + x))
succs x y = solveNat

closed : the Nat (3 * 4 + 1) = 13
closed = solveNat

zeros : (x : Nat) -> 0 * x + x * 1 = x + 0
zeros x = solveNat

-- Any other term is an atom, compared after normalisation
atoms : (f : Nat -> Nat) -> (x, y : Nat) ->
        minus x y + f (x + y) * 2 = f (x + y) + (minus x y + f (x + y))
atoms f x y = solveNat

-- Definitions which are visible are unfolded first
double : Nat -> Nat
double n = n + n

unfolded : (x : Nat) -> double (x + 1) = 2 * x + 2
unfolded x = solveNat

-- The proof is an ordinary term
useIt : (x, y : Nat) -> Vect (x + y) a -> Vect (y + x) a
useIt x y v = rewrite comm2 y x in v

main : IO ()
main = do
  -- the proofs are erased at run time; the terms they relate are not
  printLn (the (Vect 5 Nat) (useIt 2 3 [1, 2, 3, 4, 5]))

