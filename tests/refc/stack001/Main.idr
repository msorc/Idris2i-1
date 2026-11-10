module Main

import Data.List
import Data.String
import System.File

-- Much of the library is not tail recursive, so this needs a deep stack:
-- the main expression gets one of its own, whatever `ulimit -s` says.

count : Nat -> Nat
count Z = Z
count (S k) = S (count k)

main : IO ()
main = do
  let xs = [1 .. the Integer 1000000]
  printLn (foldr (+) 0 xs)
  printLn (length (map (* 2) xs ++ xs))
  printLn (take 3 (sort (reverse xs)))
  printLn (count 1000000)
  Right () <- writeFile "lines.txt" (concat (replicate 200000 "a line\n"))
    | Left err => printLn err
  Right str <- readFile "lines.txt"
    | Left err => printLn err
  printLn (length (lines str))
