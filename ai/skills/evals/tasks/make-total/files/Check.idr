module Main

import Util

main : IO ()
main = do
  printLn (toBinary 6)
  printLn (toBinary 0)
  printLn (toBinary 255)
  printLn (chunksOf 2 [1, 2, 3, 4, 5])
  printLn (chunksOf 3 (the (List Nat) []))
  printLn (chunksOf 4 ['a', 'b', 'c', 'd'])
  printLn (gcd' 12 18)
  printLn (gcd' 17 0)
  printLn (gcd' 0 9)
  printLn (msort [5, 3, 9, 1, 3, 7, 0, 2])
  printLn (msort (the (List String) ["pear", "apple", "fig"]))
  printLn (collatzSteps 1000 27)
  printLn (collatzSteps 10 27)
  printLn (collatzSteps 0 1)
