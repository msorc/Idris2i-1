||| A buffer whose size does not fit in the size that the runtime keeps (an
||| int) is an error, not a buffer of the size's low 32 bits (2^32 gave an
||| empty buffer), like an array (see refc/newArray001); a negative size is
||| Nothing.  An offset beyond an int is out of the buffer, not cut to its
||| low bits (2^32 wrote the first byte).
module Main

import Data.Buffer
import System

main : IO ()
main = do
  [_, kind, n] <- getArgs
    | _ => putStrLn "usage: main kind number"
  let k = cast {to = Int} n
  case kind of
    "new" => do
      Just b <- newBuffer k
        | Nothing => putStrLn "no buffer of size \{show k}"
      putStrLn "made a buffer of size \{show !(rawSize b)}"
    _ => do
      Just b <- newBuffer 10
        | Nothing => putStrLn "no buffer"
      setBits8 b k 42
      putStrLn "byte 0: \{show !(getBits8 b 0)}"
