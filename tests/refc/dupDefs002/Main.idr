module Main

import A
import B

-- Functions that have the same code once the functions that they call are
-- merged: leafB is leafA, then midB is midA, then topB is topA.

leafA : List Int -> Int
leafA [] = 0
leafA (x :: xs) = x + leafA xs

leafB : List Int -> Int
leafB [] = 0
leafB (x :: xs) = x + leafB xs

midA : List (List Int) -> Int
midA [] = 1
midA (x :: xs) = leafA x * midA xs

midB : List (List Int) -> Int
midB [] = 1
midB (x :: xs) = leafB x * midB xs

topA : Nat -> List (List Int) -> Int
topA Z xs = midA xs
topA (S k) xs = topA k ([1] :: xs)

topB : Nat -> List (List Int) -> Int
topB Z xs = midB xs
topB (S k) xs = topB k ([1] :: xs)

-- Functions that call each other: evenB and oddB are not merged with evenA
-- and oddA (each pair would have to be merged before the other).
mutual
  evenA : Nat -> Bool
  evenA Z = True
  evenA (S k) = oddA k

  oddA : Nat -> Bool
  oddA Z = False
  oddA (S k) = evenA k

mutual
  evenB : Nat -> Bool
  evenB Z = True
  evenB (S k) = oddB k

  oddB : Nat -> Bool
  oddB Z = False
  oddB (S k) = evenB k

-- Not the same: leafC calls leafA, and adds one more
leafC : List Int -> Int
leafC [] = 1
leafC (x :: xs) = x + leafC xs

midC : List (List Int) -> Int
midC [] = 1
midC (x :: xs) = leafC x * midC xs

main : IO ()
main = do
  let xss = [[1, 2], [3], [4, 5, 6]]
  printLn (topA 2 xss, topB 3 xss, midC xss)
  printLn (evenA 10, oddB 7, evenB 3)
  let xs = [1, 2, 50, 200]
  printLn (map (\f => map f xs) (wrapsA ++ wrapsB))
  printLn (map (\f => map f xs) (stepsA ++ stepsB), runA 1, runB 2)
