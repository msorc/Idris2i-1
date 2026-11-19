-- The C functions of these declarations of System had no prototype in
-- idris_support.h: the generated C did not compile (GCC 14 refuses an
-- implicit declaration).
import System
import System.File.Error

main : IO ()
main = do
  ok <- setEnv "IDRIS2_FOREIGNDECL" "yes" True
  printLn ok
  getEnv "IDRIS2_FOREIGNDECL" >>= printLn
  ok <- setEnv "IDRIS2_FOREIGNDECL" "no" False
  getEnv "IDRIS2_FOREIGNDECL" >>= printLn
  ok <- unsetEnv "IDRIS2_FOREIGNDECL"
  printLn ok
  getEnv "IDRIS2_FOREIGNDECL" >>= printLn
  -- (stdin is not a terminal here)
  Left _ <- enableRawMode
    | Right () => putStrLn "raw mode on a terminal?"
  putStrLn "not a terminal"
  resetRawMode
