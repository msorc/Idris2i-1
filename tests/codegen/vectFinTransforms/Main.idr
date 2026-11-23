-- The %transform rules of Data.Vect and Data.Fin: each of these functions
-- calls the run-time version (tabulateFrom, ...), not the definition.
import Data.Fin
import Data.List1
import Data.Vect

useTabulate : (n : Nat) -> Vect n Integer
useTabulate n = tabulate finToInteger

useRange : (n : Nat) -> Vect n (Fin n)
useRange n = range

useVectAllFins : (n : Nat) -> Vect n (Fin n)
useVectAllFins n = allFins n

useListAllFins : (n : Nat) -> List (Fin n)
useListAllFins n = List.allFins n

useList1AllFins : (n : Nat) -> List1 (Fin (S n))
useList1AllFins n = List1.allFins n

useLength : Vect n a -> Nat
useLength xs = length xs

useFoldr : Vect n Integer -> Integer
useFoldr xs = foldr (-) 0 xs

useStrengthen : {n : Nat} -> Fin (S n) -> Maybe (Fin n)
useStrengthen x = strengthen x

usePlus : {n : Nat} -> Fin (S n) -> Fin (S n) -> Fin (S n)
usePlus x y = x + y

useMult : {n : Nat} -> Fin (S n) -> Fin (S n) -> Fin (S n)
useMult x y = x * y

useComplement : {n : Nat} -> Fin n -> Fin n
useComplement x = complement x

-- through the dictionary of Num (Fin (S n))
%noinline
usePoly : Num a => a -> a -> a
usePoly x y = x * y + x

main : IO ()
main = do
  printLn (useTabulate 3, useRange 3, useVectAllFins 3)
  printLn (useListAllFins 3, forget (useList1AllFins 3))
  printLn (useLength [1, 2, 3], useFoldr [1, 2, 3])
  printLn (useStrengthen {n = 3} 2, useStrengthen {n = 3} 3, finS {n = 4} 3)
  printLn (usePlus {n = 4} 3 4, useMult {n = 4} 3 4, useComplement {n = 5} 1, usePoly {a = Fin 5} 3 4)
