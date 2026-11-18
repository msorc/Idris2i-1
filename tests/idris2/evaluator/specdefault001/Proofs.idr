module Proofs

-- --spec-interfaces makes no copy where there is nothing to gain at run time

data T = A | B

Uninhabited (A = B) where
  uninhabited Refl impossible

-- `absurd` takes an implementation of `Uninhabited`, an interface of proofs
fromAB : A = B -> Nat
fromAB prf = absurd prf

-- A function that computes a proof
interface Pointed a where
  point : a

pointRefl : Pointed a => point {a} = point {a}
pointRefl = Refl

Pointed Nat where
  point = 3

nat : Nat
nat = case pointRefl {a = Nat} of
           Refl => 1

-- A function called only where it is erased: in a type, and as an argument
-- of quantity 0
total' : Num a => List a -> a
total' = foldl (+) 0

data Box : Nat -> Type where
  MkBox : (0 n : Nat) -> Box n

box : Box (total' [1, 2, 3])
box = MkBox (total' [1, 2, 3])

-- ... and where it is not, to be copied
main : IO ()
main = printLn (total' [1, 2, the Integer 3], nat)
