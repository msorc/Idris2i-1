module Main

import Data.List
import Data.String

fact : Integer -> Integer
fact 0 = 1
fact n = n * fact (n - 1)

main : IO ()
main = do
  putStrLn "hello"
  printLn (fact 20)
  printLn (sum [1..10])
  putStrLn (unwords ["a", "b", "c"])
