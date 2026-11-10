module Main

import Data.Double

-- Doubles are shown like with the other backends: the shortest digits that
-- read back as the same number
doubles : List Double
doubles =
  [ 0.0, -0.0, 1.0, 100.0, 0.1, 0.1 + 0.2, 1.0 / 3.0, 123.456, 12345678.9
  , 1.0e9, 1.0e10, 1.0e22, 1.2345e19, 0.001, 1.0e-4, 2.5e-6, 1.5e-7
  , 9007199254740993.0, 1.7976931348623157e308, 2.2250738585072014e-308
  , 5.0e-324, 1.0e-310, 571012195121951.25, inf, -inf, nan
  , epsilon, unitRoundoff ]

main : IO ()
main = do
  traverse_ (putStrLn . show) doubles
  -- out of range casts wrap around
  printLn (the Int (cast (the Double 1.0e20)))
  printLn (the Int (cast (the Double (-1.0e20))))
  printLn (the Bits8 (cast (the Double 300.7)))
  printLn (the Int8 (cast (the Double (-200.0))))
  printLn (the Bits64 (cast (the Double (-1.0))))
