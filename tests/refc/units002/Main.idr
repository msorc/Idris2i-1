module Main

import Data.List
import Data.String

-- a macro of include/scale.h, which uses one of include/factor.h
%foreign "C:stamp_scale,libc,scale.h"
scale : Int -> Int

fact : Integer -> Integer
fact 0 = 1
fact n = n * fact (n - 1)

main : IO ()
main = do
  printLn (scale 21)
  printLn (fact 20)
  putStrLn (unwords ["a", "b", "c"])
