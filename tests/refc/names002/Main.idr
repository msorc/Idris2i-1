-- Names that end like the names of the C functions that the code generator
-- makes besides the function of a definition: the function of the value of a
-- constant (`x` and `x_constant`), the variant of a foreign function that
-- borrows its arguments (`absolute` and `absolute_borrow`).

%foreign "C:labs"
absolute : Int -> Int

absolute_borrow : Int -> Int
absolute_borrow n = absolute n + 1

x : Integer
x = product [1..20]

x_constant : Integer -> Integer
x_constant n = x + n

main : IO ()
main = do
  printLn (absolute (-3))
  printLn (absolute_borrow (-3))
  printLn x
  printLn (x_constant 1)
