||| The run-time versions of functions of Data.Vect and Data.Fin (the
||| `%transform` rules) against copies of the reference definitions.
module Runtime

import Data.Fin
import Data.List1
import Data.Vect

%default total

-- Copies of the definitions.  The rules do not apply to them (they are
-- other functions), so they run as they are written.
refLength : Vect n a -> Nat
refLength [] = 0
refLength (_ :: xs) = 1 + refLength xs

refTabulate : {len : Nat} -> (Fin len -> a) -> Vect len a
refTabulate {len = Z} f = []
refTabulate {len = S _} f = f FZ :: refTabulate (f . FS)

refVectAllFins : (n : Nat) -> Vect n (Fin n)
refVectAllFins Z = []
refVectAllFins (S k) = FZ :: map FS (refVectAllFins k)

refListAllFins : (n : Nat) -> List (Fin n)
refListAllFins Z = []
refListAllFins (S n) = FZ :: map FS (refListAllFins n)

refFoldr : (a -> b -> b) -> b -> Vect n a -> b
refFoldr f e [] = e
refFoldr f e (x :: xs) = f x (refFoldr f e xs)

check : Show a => Eq a => String -> List (a, a) -> IO ()
check name results
    = case filter (\(x, y) => x /= y) results of
           [] => putStrLn "\{name}: \{show (length results)} agree"
           ((x, y) :: _) => putStrLn "\{name}: MISMATCH \{show x} /= \{show y}"

sizes : List Nat
sizes = [0 .. 40]

vectOf : (n : Nat) -> Vect n Integer
vectOf n = map (\i => finToInteger i * 3 + 1) (refTabulate id)

nats : List (Fin n) -> List Nat
nats = map finToNat

main : IO ()
main = do
  check "length" [(length (vectOf n), refLength (vectOf n)) | n <- sizes]
  check "tabulate" [ (toList (Fin.tabulate {len = n} (\i => finToInteger i * 7)),
                      toList (refTabulate {len = n} (\i => finToInteger i * 7)))
                   | n <- sizes ]
  check "range" [ (nats (toList (Fin.range {len = n})), nats (toList (refTabulate {len = n} id)))
                | n <- sizes ]
  check "Vect.allFins" [(nats (toList (Vect.allFins n)), nats (toList (refVectAllFins n))) | n <- sizes]
  check "List.allFins" [(nats (List.allFins n), nats (refListAllFins n)) | n <- sizes]
  check "List1.allFins" [(nats (forget (List1.allFins n)), nats (refListAllFins (S n))) | n <- sizes]
  check "foldr" [ (foldr (\x, acc => x - 2 * acc) 5 (vectOf n),
                   refFoldr (\x, acc => x - 2 * acc) 5 (vectOf n))
                | n <- sizes ]
  printLn (Fin.range {len = 5}, Vect.allFins 4)
  printLn (List1.allFins 2, Vect.length (vectOf 7))

-- The definitions still reduce as before at type-checking time.
tabulate3 : tabulate {len = 3} Fin.finToNat = [0, 1, 2]
tabulate3 = Refl

length3 : Vect.length (the (Vect 3 Nat) [1, 2, 3]) = 3
length3 = Refl

allFins2 : List.allFins 2 = [FZ, FS FZ]
allFins2 = Refl
