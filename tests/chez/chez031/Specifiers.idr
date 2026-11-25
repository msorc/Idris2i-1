module Specifiers

{- This tests both the given specifiers and the error reporting of them.
   To this end it tests via:
   -o foo           -- testing cli compilation
   --exec main      -- testing cli execution

   > :exec main     -- testing repl execution

   > :set eval exec -- testing repl evaluation with eval set to execute
   > main
-}

-- Generic match good for any scheme backend
%foreign "scheme:+"
plusGeneric : Int -> Int -> Int

-- We're testing with --cg chez so this specifier should be chosen.
%foreign "scheme,chez:+"
plusChez : Int -> Int -> Int

-- We're testing with --cg chez so this should match C because chez accepts C
-- specifiers but the next test should fail.
%foreign "scheme,gambit:+"
         "C:notreal,notalib"
plusGambitOK : Int -> Int -> Int

-- We're testing with --cg chez so this shouldn't find a valid specifier to use.
%foreign "scheme,gambit:+"
plusGambitFail : Int -> Int -> Int

-- We don't actually do any printing this is just to use the specifiers so the
-- failures are exposed.
main : IO ()
main = do
  printLn $ plusGeneric 2 3
  printLn $ plusChez 2 3
  printLn $ plusGambitOK 2 3
  printLn $ plusGambitFail 2 3
  pure ()
