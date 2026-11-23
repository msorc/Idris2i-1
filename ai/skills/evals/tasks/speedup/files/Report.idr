module Main

import Data.List
import Data.Maybe
import Data.String
import System

||| The primes below a limit, by trial division.
primesBelow : Integer -> List Integer
primesBelow limit = go [] 2
  where
    go : List Integer -> Integer -> List Integer
    go found n =
      if n >= limit then reverse found
      else if any (\p => n `mod` p == 0) found then go found (n + 1)
      else go (n :: found) (n + 1)

||| Number of steps of the Collatz iteration from n to 1.
collatz : Integer -> Integer
collatz n = if n == 1 then 0
            else if n `mod` 2 == 0 then 1 + collatz (n `div` 2)
            else 1 + collatz (3 * n + 1)

||| One line per number from 1 to limit: the number, its Collatz length, and
||| whether it is prime.
report : Integer -> String
report limit = go "" 1
  where
    primes : List Integer
    primes = primesBelow (limit + 1)

    line : Integer -> String
    line n = show n ++ " " ++ show (collatz n) ++ (if elem n primes then " prime" else "") ++ "\n"

    go : String -> Integer -> String
    go acc n = if n > limit then acc else go (acc ++ line n) (n + 1)

||| A checksum of a text: the sum of position times character code, modulo 1000003.
partial
checksum : String -> Integer
checksum s = go 0 0
  where
    partial
    go : Integer -> Integer -> Integer
    go i acc =
      if i >= cast (length s) then acc
      else go (i + 1) ((acc + (i + 1) * cast (ord (strIndex s (cast i)))) `mod` 1000003)

partial
main : IO ()
main = do
  [_, arg] <- getArgs
    | _ => die "usage: report LIMIT"
  let limit = fromMaybe 100 (parsePositive arg)
  let text = report limit
  putStr (unlines (take 5 (lines text)))
  putStrLn ("lines " ++ show (length (lines text)))
  putStrLn ("checksum " ++ show (checksum text))
