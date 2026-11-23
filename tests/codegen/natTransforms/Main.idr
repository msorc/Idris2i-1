-- The %transform rules of Data.Nat: each of these functions calls the
-- run-time version on Integer (lteInteger, ...), not the unary definition.
import Data.Nat
import Decidable.Equality

useLte : Nat -> Nat -> Bool
useLte = lte

useGt : Nat -> Nat -> Bool
useGt x y = gt x y

useMinimum : Nat -> Nat -> Nat
useMinimum x y = minimum x y

useMaximum : Nat -> Nat -> Nat
useMaximum x y = maximum x y

usePower : Nat -> Nat -> Nat
usePower x y = power x y

useDiv' : Nat -> Nat -> Nat -> Nat
useDiv' f x y = div' f x y

useMod' : Nat -> Nat -> Nat -> Nat
useMod' f x y = mod' f x y

useDivmod' : Nat -> Nat -> Nat -> (Nat, Nat)
useDivmod' f x y = divmod' f x y

useIsLTE : (m, n : Nat) -> Bool
useIsLTE m n = case isLTE m n of
                    Yes _ => True
                    No _ => False

useDecEq : (m, n : Nat) -> Bool
useDecEq m n = case decEq m n of
                    Yes _ => True
                    No _ => False

-- through the dictionary of DecEq Nat
%noinline
usePoly : DecEq a => a -> a -> Bool
usePoly x y = case decEq x y of
                   Yes _ => True
                   No _ => False

useDiv : Nat -> Nat -> Nat
useDiv x y = x `div` S y

main : IO ()
main = do
  printLn [useLte 3 4, useGt 3 4, useIsLTE 3 4, useIsLTE 4 3, useDecEq 3 3, useDecEq 3 4, usePoly (the Nat 3) 4]
  printLn [useMinimum 3 4, useMaximum 3 4, usePower 3 4, useDiv' 9 9 1, useMod' 9 9 1]
  printLn (useDivmod' 9 9 1, gcd 12 18, useDiv 9 1)
