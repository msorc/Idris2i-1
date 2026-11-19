module Main

import Data.IORef
import System
import System.Concurrency

-- The functions of the backtraces are %noinline, so that the Idris compiler
-- keeps them, and they call each other in positions that are not tail calls,
-- so that their frames are in the continuation when the program dies.

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

-- An error that Chez raises: infinity has no exact value.
%noinline
toInteger : Double -> Integer
toInteger x = 1 + cast x

%noinline partial
depth : Int -> Int
depth 0 = idris_crash "deep"
depth n = 1 + depth (n - 1)

%noinline partial
run : String -> String
run "crash" = show (sumChecked [1, 2, 300, 4])
run "case" = describe Blue
run w@"div" = show (divide 1 (cast (length w) - 3))
run "chez" = show (toInteger (1.0 / 0.0))
run "deep" = show (depth 100000)
run _ = "which crash?"

-- Wait until the flag is set, at most 30 seconds.
covering
waitFor : IORef Bool -> Nat -> IO ()
waitFor flag Z = pure ()
waitFor flag (S n) = do
  set <- readIORef flag
  if set then pure () else usleep 10000 >> waitFor flag n

partial
main : IO ()
main = do
  [_, what, wher] <- getArgs
    | _ => putStrLn "which crash, and where?"
  case wher of
    "thread" => do
      -- (the thread tells that it runs; whatever the load of the machine,
      -- the main thread then gives it a second to print the backtrace and
      -- end before it goes on)
      started <- newIORef False
      _ <- fork (writeIORef started True >> putStrLn (run what))
      -- (an error that Chez raises ends the thread only)
      waitFor started 3000
      sleep 1
      putStrLn "the main thread goes on"
    _ => putStrLn (run what)
