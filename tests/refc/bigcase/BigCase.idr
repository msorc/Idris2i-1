-- A case on constants that do not fit in 32 bits (they used to be truncated).

int : Int -> String
int 0 = "zero"
int 4294967296 = "2^32"
int 9223372036854775807 = "max"
int (-9223372036854775808) = "min"
int _ = "other"

bits64 : Bits64 -> String
bits64 0 = "zero"
bits64 4294967296 = "2^32"
bits64 18446744073709551615 = "max"
bits64 _ = "other"

integer : Integer -> String
integer 0 = "zero"
integer 4294967296 = "2^32"
integer 340282366920938463463374607431768211456 = "2^128"
integer (-1) = "minus one"
integer _ = "other"

char : Char -> String
char 'a' = "a"
char '\n' = "newline"
char 'λ' = "lambda"
char _ = "other"

two128 : Integer
two128 = 340282366920938463463374607431768211456

main : IO ()
main = do
  printLn (map int [0, 4294967296, 1, 9223372036854775807, -9223372036854775808, 4294967297])
  printLn (map bits64 [0, 4294967296, 18446744073709551615, 7])
  printLn (map integer [0, 4294967296, two128, -1, two128 + 4294967296, 4294967296 * 4294967296 * 4294967296 * 4294967296])
  printLn (map char ['a', '\n', 'λ', 'b'])
