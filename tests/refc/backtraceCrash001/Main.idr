module Main

import System

-- The functions of the backtraces are %noinline, so that the Idris compiler
-- keeps them, and they call each other in positions that are not tail calls,
-- so that their frames are on the stack when the program dies.

data Colour = Red | Green | Blue

%noinline partial
name : Colour -> String
name Red = "red"
name Green = "green"

%noinline partial
describe : Colour -> String
describe c = "the colour " ++ name c

%noinline partial
checked : Int -> Int
checked n = if n > 100 then idris_crash "too big" else n

%noinline partial
sumChecked : List Int -> Int
sumChecked [] = 0
sumChecked (x :: xs) = checked x + sumChecked xs

%noinline
divide : Int -> Int -> Int
divide x y = 1 + x `div` y

partial
main : IO ()
main = do
  [_, what] <- getArgs
    | _ => putStrLn "which crash?"
  case what of
    "crash" => printLn (sumChecked [1, 2, 300, 4])
    "case" => putStrLn (describe Blue)
    "div" => printLn (divide 1 (cast (length what) - 3))
    _ => putStrLn "which crash?"
