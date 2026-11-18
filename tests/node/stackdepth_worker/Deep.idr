module Deep

import Data.List
import Data.String
import System
import System.Directory

-- Deep recursion that is not a tail call: before the main expression ran on
-- a stack of its own, Node's stack overflowed at a few thousand elements.

sumR : List Integer -> Integer
sumR [] = 0
sumR (x :: xs) = x + sumR xs

-- A monadic loop through an unknown monad: each iteration nests a call.
countM : Monad m => Nat -> Integer -> m Integer
countM Z acc = pure acc
countM (S k) acc = do
  x <- pure (acc + 1)
  countM k x

main : IO ()
main = do
  let n = 200000
  let xs = map cast [1 .. the Nat n]
  printLn (sumR xs)
  printLn (foldr (+) 0 xs)
  printLn (sum (take 10 (sort (map (\x => (x * 7919) `mod` 100003) xs))))
  printLn (countM {m = Maybe} n 0)
  r <- countM {m = IO} n 0
  printLn r
  -- standard input, the working directory and the exit code still work
  l <- getLine
  putStrLn "read: \{trim l}"
  ok <- changeDir "testdir"
  printLn ok
  _ <- system "ls"
  exitWith (ExitFailure 3)
