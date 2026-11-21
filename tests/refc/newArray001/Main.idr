||| An array whose length does not fit in the length that the runtime keeps
||| (an int) is an error, not an array of the length's low 32 bits (2^32 gave
||| an empty array, 2^32 + 1 one of length 1, that writes ran over), and so
||| is an array of a negative length (only the primitive allows it).
module Main

import Data.IOArray
import Data.IOArray.Prims
import System

main : IO ()
main = do
  [_, kind, n] <- getArgs
    | _ => putStrLn "usage: main kind length"
  let len = cast {to = Int} n
  case kind of
    "array" => do
      a <- newArray {elem = Int} len
      putStrLn "made an array of length \{show (max a)}"
    "flat" => do
      a <- newFlatArray {elem = Double} len
      putStrLn "made a flat array of length \{show (max a)}"
    _ => do
      _ <- primIO (prim__newArray len (the Int 0))
      putStrLn "made a primitive array of length \{show len}"
