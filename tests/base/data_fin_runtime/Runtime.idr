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
