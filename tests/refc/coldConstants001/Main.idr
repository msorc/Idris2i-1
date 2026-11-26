-- The functions that evaluate the constants of a program are `cold`
-- (IDRIS2I_1_CONSTANT_MAKER), but for the main expression.
squares : List Integer
squares = map (\x => x * x) [1 .. 1000]

total' : Integer
total' = sum squares

main : IO ()
main = do
  printLn total'
  printLn (length squares)
