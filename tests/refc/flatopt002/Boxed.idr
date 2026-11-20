||| A program that does not use the flat arrays: compiled as without them
||| (no layout, no access by fields, the array primitives of before).
module Boxed

import Data.IOArray

record Q where
  constructor MkQ
  a : Int
  b : Int

main : IO ()
main = do
  arr <- newArray {elem = Q} 8
  for_ [0 .. 7] $ \i => ignore (writeArray arr i (MkQ i (i * i)))
  Just q <- readArray arr 5 | Nothing => pure ()
  printLn (q.a + q.b)
