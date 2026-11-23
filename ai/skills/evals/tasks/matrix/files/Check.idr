module Main

import Data.Vect
import Matrix

%default total

m23 : Matrix 2 3 Integer
m23 = [[1, 2, 3], [4, 5, 6]]

m32 : Matrix 3 2 Integer
m32 = [[7, 8], [9, 10], [11, 12]]

empty : Matrix 0 4 Integer
empty = []

t : Matrix 3 2 Integer
t = transposeM m23

product : Matrix 2 2 Integer
product = mulM m23 m32

sameShape : Matrix 2 3 Integer
sameShape = mulM (identityM 2) m23

doubles : Matrix 2 2 Double
doubles = mulM [[0.5, 0], [0, 2]] (identityM 2)

-- The dimensions are available at run time without being passed.
dims : (Nat, Nat)
dims = (rowsM m32, colsM m32)

main : IO ()
main = do
  putStrLn (showM t)
  putStrLn (showM product)
  putStrLn (showM sameShape)
  putStrLn (showM (mulM m32 (identityM 2)))
  putStrLn (showM doubles)
  printLn (rowsM (transposeM empty), colsM (transposeM empty))
  printLn dims
  putStrLn (showM (transposeM (transposeM m23)))
