||| The run-time versions that rely on the representation of `Nat`-shaped
||| types (`LTE`, `Fin`) as `Integer`, against copies of the reference
||| definitions, over ranges that include the boundaries.  The proofs and
||| `Fin`s they make are taken apart by pattern matching, so a wrong
||| representation shows up as a wrong number.
module Runtime

import Data.Fin
import Data.Nat
import Decidable.Equality

%default total

-- Copies of the definitions.  The rules do not apply to them.
refIsLTE : (m, n : Nat) -> Dec (LTE m n)
refIsLTE Z n = Yes LTEZero
refIsLTE (S k) Z = No succNotLTEzero
refIsLTE (S k) (S j)
    = case refIsLTE k j of
           No contra => No (contra . fromLteSucc)
           Yes prf => Yes (LTESucc prf)

refDecEq : (n, m : Nat) -> Dec (n = m)
refDecEq Z     Z     = Yes Refl
refDecEq (S n) (S m) = decEqCong $ refDecEq n m
refDecEq Z     (S _) = No absurd
refDecEq (S _) Z     = No absurd

yes : Dec p -> Bool
yes (Yes _) = True
yes (No _) = False

-- decEq through a DecEq dictionary
decEqPoly : DecEq a => a -> a -> Bool
decEqPoly x y = yes (decEq x y)

-- The proof of an equality, used at run time to change the type of a value
castBy : (n, m : Nat) -> List (Fin (S n)) -> Maybe (List (Fin (S m)))
castBy n m xs = case decEq n m of
                     Yes prf => Just (rewrite sym prf in xs)
                     No _ => Nothing

refStrengthen : {n : _} -> Fin (S n) -> Maybe (Fin n)
refStrengthen {n = S _} FZ = Just FZ
refStrengthen {n = S _} (FS p) with (refStrengthen p)
  refStrengthen (FS _) | Nothing = Nothing
  refStrengthen (FS _) | Just q  = Just $ FS q
refStrengthen _ = Nothing

refFinS : {n : Nat} -> Fin n -> Fin n
refFinS {n = S _} x = case refStrengthen x of
    Nothing => FZ
    Just y => FS y

-- The number of LTESucc in a proof, by matching on it
size : LTE m n -> Nat
size LTEZero = 0
size (LTESucc p) = S (size p)

dec : Dec (LTE m n) -> Maybe Nat
dec (Yes p) = Just (size p)
dec (No _) = Nothing

-- The Fin by matching on it
unFin : Fin n -> Nat
unFin FZ = 0
unFin (FS k) = S (unFin k)

check : Show a => Eq a => String -> List (a, a) -> IO ()
check name results
    = case filter (\(x, y) => x /= y) results of
           [] => putStrLn "\{name}: \{show (length results)} agree"
           ((x, y) :: _) => putStrLn "\{name}: MISMATCH \{show x} /= \{show y}"

-- All the Fins of a bound, built with FS
fins : (n : Nat) -> List (Fin n)
fins Z = []
fins (S k) = FZ :: map FS (fins k)

range : Nat -> List Nat
range n = [0 .. n]

pairs : Nat -> List (Nat, Nat)
pairs n = [(a, b) | a <- range n, b <- range n]

main : IO ()
main = do
  check "isLTE" [(dec (isLTE a b), dec (refIsLTE a b)) | (a, b) <- pairs 25]
  check "isGTE" [(dec (isGTE a b), dec (refIsLTE b a)) | (a, b) <- pairs 25]
  check "isLT" [(dec (isLT a b), dec (refIsLTE (S a) b)) | (a, b) <- pairs 25]
  check "isGT" [(dec (isGT a b), dec (refIsLTE (S b) a)) | (a, b) <- pairs 25]
  let big = the Nat 98765432109876543210
  printLn (dec (isLTE big (big + 1)), dec (isLTE (big + 1) big))
  check "decEq" [(yes (decEq a b), yes (refDecEq a b)) | (a, b) <- pairs 25]
  check "decEq (poly)" [(decEqPoly a b, yes (refDecEq a b)) | (a, b) <- pairs 25]
  check "decEq (List Nat)" [(decEqPoly [a, b] [b, a], a == b) | (a, b) <- pairs 25]
  printLn (map (map finToNat) (castBy 2 2 [0, 1, 2]), map (map finToNat) (castBy 2 3 [0, 1]))
  printLn (yes (decEq big big), yes (decEq big (big + 1)))
  check "strengthen" [ (map unFin (strengthen x), map unFin (refStrengthen x))
                     | n <- range 20, x <- fins (S n) ]
  check "finS" [(unFin (finS x), unFin (refFinS x)) | n <- range 20, x <- fins n]
  printLn (map finToNat (strengthen (the (Fin 101) 99)), map finToNat (strengthen (the (Fin 101) 100)))
