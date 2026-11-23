module Util

import Data.List
import Data.Nat

||| Binary digits of a number, least significant first: toBinary 6 = [False, True, True].
export
toBinary : Nat -> List Bool
toBinary 0 = []
toBinary n = (n `mod` 2 == 1) :: toBinary (n `div` 2)

||| Split a list into pieces of the given length; the last piece may be shorter.
export
chunksOf : Nat -> List a -> List (List a)
chunksOf n [] = []
chunksOf n xs = take n xs :: chunksOf n (drop n xs)

||| Greatest common divisor.
export
gcd' : Nat -> Nat -> Nat
gcd' a 0 = a
gcd' a b = gcd' b (a `mod` b)

||| Merge two sorted lists.
merge' : Ord a => List a -> List a -> List a
merge' [] ys = ys
merge' xs [] = xs
merge' (x :: xs) (y :: ys) =
  if x <= y then x :: merge' xs (y :: ys) else y :: merge' (x :: xs) ys

||| Merge sort.
export
msort : Ord a => List a -> List a
msort [] = []
msort [x] = [x]
msort xs =
  let (l, r) = splitAt (length xs `div` 2) xs in
  merge' (msort l) (msort r)

||| Number of steps of the Collatz iteration from n down to 1, if it gets there
||| within the given number of steps.
export
collatzSteps : (limit : Nat) -> Nat -> Maybe Nat
collatzSteps limit n = go 0 n
  where
    go : Nat -> Nat -> Maybe Nat
    go steps 1 = Just steps
    go steps k =
      if steps >= limit then Nothing
      else go (S steps) (if k `mod` 2 == 0 then k `div` 2 else 3 * k + 1)
