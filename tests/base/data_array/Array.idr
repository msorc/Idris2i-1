import Data.Array
import Data.Vect
import Data.Fin

a : Array 5 Nat
a = tabulate (\i => finToNat i * 10)

-- every index of a larger array, against the Vect it came from
big : Vect 1000 Integer
big = Fin.tabulate (\i => finToInteger i * finToInteger i)

bigArray : Array 1000 Integer
bigArray = fromVect big

main : IO ()
main = do
  printLn a
  printLn (Array.index 3 a, size a, sum a)
  printLn (foldr (::) [] a)
  printLn (foldl (flip (::)) [] a)
  printLn (map (+1) a)
  printLn (replaceAt 0 99 a)
  printLn (updateAt 4 (*2) a)
  printLn (zipWith (+) a a)
  printLn (zipWith3 (\x, y, z => x + y * z) a a a)
  printLn (unzipWith (\x => (x, x * 2)) a)
  printLn (a == a, a == replaceAt 2 0 a)
  printLn (toVect a)
  printLn (empty {a = Nat}, size (empty {a = Nat}), null (empty {a = Int}))
  printLn (fromVect [1, 2, 3])
  let (n ** b) = Array.fromList ['a', 'b', 'c']
  printLn (n, b, null b)
  let (m ** c) = Array.fromList (the (List Int) [])
  printLn (m, c)
  printLn (Array.replicate 3 'x')
  -- replaceAt copies: the original is unchanged
  let a' = replaceAt 1 7 a
  printLn (a', a)
  printLn (all (\i => Array.index i bigArray == Vect.index i big) (Vect.allFins 1000))
  printLn (toList (toVect bigArray) == toList big, sum bigArray)
