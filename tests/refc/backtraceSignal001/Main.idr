module Main

import System

-- Foreign functions that die of a signal (see crashers.h), called in
-- positions that are not tail calls.

%foreign "C:bt_segv,libcrashers,crashers.h"
segv : Int -> Int

%foreign "C:bt_fpe,libcrashers,crashers.h"
fpe : Int -> Int

%foreign "C:bt_abort,libcrashers,crashers.h"
abrt : Int -> Int

%foreign "C:bt_bus,libcrashers,crashers.h"
bus : Int -> Int

%noinline
compute : String -> Int -> Int
compute "segv" x = 1 + segv x
compute "fpe" x = 1 + fpe x
compute "abort" x = 1 + abrt x
compute "bus" x = 1 + bus x
compute _ x = x

%noinline
twice : String -> Int -> Int
twice s x = compute s x + compute s (x + 1)

main : IO ()
main = do
  [_, what] <- getArgs
    | _ => putStrLn "which signal?"
  printLn (twice what 1)
