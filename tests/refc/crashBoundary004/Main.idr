-- Crash boundaries: the backtrace of a caught crash (with the names that
-- `--directive refc-backtrace` gives), down to the boundary; and the
-- failures that stay fatal inside a boundary: a crash in a finaliser, a
-- stack overflow, a Mutex released by a thread that does not hold it.
module Main

import Data.IORef
import Data.List
import System
import System.Concurrency
import System.Crash

%default partial

describe : Int -> String
describe 0 = "zero"

name : Int -> String
name n = "<" ++ describe n ++ ">"

%noinline
mix : Int -> Int -> Int
mix a b = a * 31 + b

-- A recursion that is not a tail call, for a stack overflow.
deep : Int -> Int
deep 0 = 0
deep n = mix (deep (n - 1)) n

-- (the arguments are made at run time, so that the compiler does not fold
-- them)
main : IO ()
main = do
  args <- getArgs
  let n = cast (length args)
  case drop 1 args of
    ["backtrace"] => do
      Left c <- catchCrash (pure (name n))
        | Right s => putStrLn s
      putStrLn (show c)
      putStr (fromMaybe "no backtrace\n" c.backtrace)
      -- the program goes on, and a crash outside the boundary is fatal
      putStrLn (name (n + 1))
    ["finaliser"] => do
      _ <- catchCrash $ do
        p <- onCollectAny prim__getNullAnyPtr (\_ => putStrLn (name n))
        -- (the GC pointer is dropped here: the finaliser runs)
        pure ()
      putStrLn "not reached"
    ["overflow"] => do
      _ <- catchCrash (pure (deep (100000000 + n)))
      putStrLn "not reached"
    ["mutex"] => do
      m <- makeMutex
      _ <- catchCrash (mutexRelease m)
      putStrLn "not reached"
    _ => putStrLn "?"
  where
    fromMaybe : String -> Maybe String -> String
    fromMaybe d Nothing = d
    fromMaybe _ (Just s) = s
