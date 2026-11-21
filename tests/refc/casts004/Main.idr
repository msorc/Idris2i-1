||| Casting a NaN or an infinity to an Integer gives 0, as the casts to the
||| fixed width integers do (GMP raised SIGFPE; the Chez backend raises an
||| exception).
module Main

import Data.IORef

-- (read at run time: the casts are not folded)
runtime : a -> IO a
runtime x = newIORef x >>= readIORef

main : IO ()
main = do
  ds <- runtime [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0, -2.5, 1.0e20]
  printLn (map (cast {to = Integer}) ds)
  printLn (map (cast {to = Int}) ds)
  printLn (map (cast {to = Bits8}) ds)
