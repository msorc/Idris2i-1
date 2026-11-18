module Main

-- (only the Prelude, which the test builds with Chez code)

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

%noinline partial
depth : Int -> Int
depth 0 = idris_crash "deep"
depth n = 1 + depth (n - 1)

partial
main : IO ()
main = do
  what <- getLine
  case what of
    "crash" => printLn (sumChecked [1, 2, 300, 4])
    "case" => putStrLn (describe Blue)
    "deep" => printLn (depth 1000)
    _ => putStrLn "which crash?"
