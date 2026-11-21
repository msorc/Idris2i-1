||| `show` gives the shortest digits that read back as the Double, as in the
||| Chez backend, also when they are not the digits nearest to it: the
||| Doubles next to a power of two are not at the same distance on both sides
||| (5.986310706507378e51 printed as 5.9863107065073784e51).  Every power of
||| two, and the Doubles next to some of them.
module Main

import Data.IORef

-- (read at run time: nothing is folded)
runtime : a -> IO a
runtime x = newIORef x >>= readIORef

powers : Double -> Double -> Nat -> List Double
powers x f Z = []
powers x f (S k) = x :: powers (x * f) f k

main : IO ()
main = do
  one <- runtime 1.0
  for_ (powers one 2.0 1024 ++ powers (one / 2.0) 0.5 1074) $ \d =>
    putStrLn (show d)
  -- reading the shown text gives the Double back (for the normal ones: the
  -- cast does not read the "|<bits>" after a subnormal one with RefC)
  ds <- runtime [5.986310706507378e51, 5.986310706507379e51,
                 5.986310706507377e51, 2.2250738585072014e-308,
                 1.7976931348623157e308]
  printLn ds
  let normal = powers one 2.0 1024 ++ powers (one / 2.0) 0.5 1022 ++ ds
  printLn (all (\d => cast {to = Double} (show d) == d) normal)
