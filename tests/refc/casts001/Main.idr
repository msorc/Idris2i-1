||| A fraction with a zero denominator is not a number, as in the Chez
||| backend: casting it gives 0 (GMP divided by zero, which raised SIGFPE).
module Main

import Data.IORef

-- (read at run time: the casts are not folded)
runtime : a -> IO a
runtime x = newIORef x >>= readIORef

main : IO ()
main = do
  ss <- runtime ["1/0", "-3/0", "0/0", "+5/0", "1/00", "-7/000", "1/01"]
  printLn (map (cast {to = Integer}) ss)
  printLn (map (cast {to = Int}) ss)
  printLn (map (cast {to = Int8}) ss)
  printLn (map (cast {to = Bits64}) ss)
  printLn (map (cast {to = Double}) ss)
