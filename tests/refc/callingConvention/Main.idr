module Main

%default total

dupargs : Integer -> Integer
dupargs x = x + x

last : List a -> a -> a
last [] x = x
last (y :: ys) _ = last ys y

covering main : IO () -- ranges of Integer use Integral Integer (partial div)
main = do
  flip for_ (printLn . (`last` 0))
     $ [] :: map (\ x => [1..x]) [1..5]
  printLn $ dupargs 9999

