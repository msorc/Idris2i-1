||| Casting a Double to a fixed width integer truncates it and wraps around
||| exactly, as in the Chez backend, also for -2^64 < d <= -9.2e18, which
||| went through a rounding addition of 2^64 (-2^63 + 1024 gave -2^63).
module Main

import Data.IORef
import Data.String

-- (read at run time: the casts are not folded)
runtime : a -> IO a
runtime x = newIORef x >>= readIORef

main : IO ()
main = do
  ds <- runtime [-9223372036854774784.0, -9223372036854775808.0, -9.2e18,
                 -9.3e18, 9.3e18, -18446744073709549568.0,
                 18446744073709549568.0, -1.8446744073709552e19, -2.0e19,
                 1.0e30, -1.0e30, 9223372036854775808.0,
                 -9223372036854777856.0]
  for_ ds $ \d =>
    putStrLn $ unwords
      [show (cast {to = Int} d), show (cast {to = Int64} d),
       show (cast {to = Bits64} d), show (cast {to = Int32} d),
       show (cast {to = Bits32} d), show (cast {to = Int16} d),
       show (cast {to = Bits8} d)]
