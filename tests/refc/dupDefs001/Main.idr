module Main

import Data.String

-- Pairs of functions that have the same code but for their names: the C
-- code of each pair is written once.

data T = A | B Int T

sumT : T -> Int
sumT A = 0
sumT (B x t) = x + sumT t

sumU : T -> Int
sumU A = 0
sumU (B x t) = x + sumU t

lenL : List a -> Nat
lenL [] = 0
lenL (_ :: xs) = S (lenL xs)

lenM : List a -> Nat
lenM [] = 0
lenM (_ :: xs) = S (lenM xs)

-- (with workers, which take and give C integers)
addB : Bits64 -> Bits64 -> Bits64
addB a b = a * 3 + b

addC : Bits64 -> Bits64 -> Bits64
addC a b = a * 3 + b

-- Big enough to be written once even in different units of a split program
bigA : Int -> String -> String
bigA 0 s = "zero " ++ s
bigA 1 s = "one " ++ s ++ s
bigA 2 s = "two " ++ reverse s
bigA 3 s = "three " ++ show (length s)
bigA 4 s = "four " ++ pack (filter isDigit (unpack s))
bigA 5 s = "five " ++ toUpper s
bigA 6 s = "six " ++ toLower s
bigA 7 s = "seven " ++ concat (replicate 3 s)
bigA 8 s = "eight " ++ show (words s)
bigA 9 s = "nine " ++ show (lines s)
bigA n s = show n ++ " " ++ s

bigB : Int -> String -> String
bigB 0 s = "zero " ++ s
bigB 1 s = "one " ++ s ++ s
bigB 2 s = "two " ++ reverse s
bigB 3 s = "three " ++ show (length s)
bigB 4 s = "four " ++ pack (filter isDigit (unpack s))
bigB 5 s = "five " ++ toUpper s
bigB 6 s = "six " ++ toLower s
bigB 7 s = "seven " ++ concat (replicate 3 s)
bigB 8 s = "eight " ++ show (words s)
bigB 9 s = "nine " ++ show (lines s)
bigB n s = show n ++ " " ++ s

main : IO ()
main = do
  let t = B 1 (B 2 (B 3 A))
  printLn (sumT t, sumU t)
  printLn (lenL [1, 2, 3], lenM ["a"])
  -- (called directly, and through closures)
  let fs = [addB, addC]
  printLn (map (\f => f 5 7) fs, addB 1 2 + addC 3 4)
  let gs = [bigA, bigB]
  traverse_ (\n => putStrLn (unwords (map (\g => g n "a1 b2") gs))) [0 .. 10]
