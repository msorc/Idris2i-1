-- A caught crash under Valgrind (see `run`): no memory errors, and the leak
-- of a crash is what the crashed code held.
module Main

import Data.List
import System
import System.Crash

%default partial

%noinline
check : Int -> Int
check i = if i >= 0 then assert_total (idris_crash ("request " ++ show i)) else i

act : Int -> IO Int
act i = do
  let s = pack (replicate 100 'x')
  let r = check i
  pure (r + cast (length s))

loop : Int -> IO ()
loop 0 = pure ()
loop i = do ignore (catchCrash (act i)); loop (i - 1)

main : IO ()
main = do
  [_, k] <- getArgs
    | _ => putStrLn "usage: crash <crashes>"
  loop (cast k)
  putStrLn ("crashes caught: " ++ show !crashesCaught)
