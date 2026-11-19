module Literals

-- Number literals in the generated JavaScript: a subnormal Double (which
-- `show` prints as `5e-324|1`), negative zero, and negative constants after
-- an operator (`x - -5n`).  Only Bools and Integers are printed, so the
-- output is the same as with Chez and RefC.

smallest : Double
smallest = 4.9e-324

subnormals : List Double
subnormals = [4.9e-324, 1.0e-323, 2.5e-320, 2.2250738585072009e-308, 2.2250738585072014e-308]

minusInteger : Integer -> Integer
minusInteger x = x - (-5)

minusInt : Int -> Int
minusInt x = x - (-5)

minusDouble : Double -> Double
minusDouble x = x - (-2.5)

negZero : Double
negZero = -0.0

main : IO ()
main = do
  printLn (smallest > 0.0, smallest < 1.0e-323, smallest / 2.0 == 0.0)
  printLn (smallest * 2.0 == 1.0e-323, smallest + smallest == 9.9e-324)
  printLn (map (> 0.0) subnormals)
  printLn (map (\x => x * 4503599627370496.0 * 4503599627370496.0 > 1.0e-292) subnormals)
  printLn (2.2250738585072009e-308 < 2.2250738585072014e-308)
  printLn (1.0 / negZero < 0.0, 1.0 / 0.0 > 0.0, negZero == 0.0)
  printLn (minusInteger 1, minusInt 1, minusDouble 1.0 == 3.5)
  printLn (1.7976931348623157e308 > 1.0e308, 1.0e21 == 1000000000000000000000.0)
