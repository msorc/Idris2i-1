module Main
import A
import B
import Base
main : IO ()
main = do
  printLn (useA [[1,2],[3]])
  printLn (useB [[4]])
  printLn (total2 [[the Int 5]])
