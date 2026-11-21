||| A decimal number may end with a mantissa width, `|<bits>`, as `show` writes
||| after a subnormal Double, and as in the Chez backend: the number is rounded
||| to that many bits (to the nearest, ties to even), then to a Double; the
||| width follows an integer, a decimal or an exponent, but not a fraction.
||| Casts to the integers truncate that Double.
module Main

import Data.IORef

-- (read at run time: the casts are not folded)
runtime : a -> IO a
runtime x = newIORef x >>= readIORef

main : IO ()
main = do
  ds <- runtime
          ["5e-324|1", "-5e-324|1", "4.9406564584124654e-324|1", "3e-324|1",
           "7.4e-323|4", "1e-310|3", "1.1125369292536007e-308|52",
           "1.1125369292536007e-308|5", "2.2250738585072014e-308|52",
           "1.5|1", "2.5|1", "3.5|1", "0.75|1", "1.25|2", "-.75|1", ".5|3",
           "5.|3", "+.5|1", "0.1|3", "0.1|53", "0.1|60", "12|5", "13|2",
           "5|1", "6|1", "6|2", "-12.7|2", "1e3|10", "1.0E2|3",
           "9007199254740993|54", "9007199254740993|60",
           "1.0000000000000002220446049250313080847263336181640625|52",
           "1.00000000000000011102230246251565404236316680908203126|54",
           "1e308|3", "1.7976931348623157e308|2", "1e400|5", "1e99999|3",
           "-1e-400|5", "-1e-99999|3", "1.0|0", "-1.0|0", "0|5", "-0|5",
           "7|0", "1.0|00000000000000000000000000000000000000000001",
           "1.0|99999999999999999999999999", "12|99999999999999999999999",
           -- no numbers
           "1|", "|5", "1.0|-2", "1.0|+2", "1.0|2|3", "1.0| 2", "+inf.0|5",
           "1/2|5"]
  for_ ds $ \s => putStrLn "\{s} \{show (cast {to = Double} s)}"
  -- (the finite ones: Chez raises an exception for an infinity)
  is <- runtime ["1.5|1", "-.75|1", "13|2", "-12.7|2", "1.0E2|3", "1e308|3",
                 "-5e-324|1", "-0|5", "1|", "1/2|5"]
  printLn (map (cast {to = Integer}) is)
  printLn (map (cast {to = Int}) is)
  printLn (map (cast {to = Bits8}) is)
