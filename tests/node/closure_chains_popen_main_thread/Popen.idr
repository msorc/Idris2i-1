module Popen

-- popen, pclose, popen2 and popen2Wait on Node, in its worker thread and on
-- the main thread (IDRIS2_MAIN_STACK_SIZE=0): the same output, which is that
-- of Chez and RefC.

import System
import System.File

%default covering

say : String -> IO ()
say = putStrLn

showE : Show a => Either FileError a -> String
showE (Left e) = "Left " ++ show e
showE (Right x) = "Right " ++ show x

main : IO ()
main = do
  -- reading, while the command runs
  Right f <- popen "echo first; sleep 1; echo second; exit 3" Read
    | Left e => say ("popen: " ++ show e)
  say ("first: " ++ showE !(fGetLine f))
  say ("second: " ++ showE !(fGetLine f))
  say ("end: " ++ showE !(fGetLine f))
  say ("pclose: " ++ show !(pclose f))
  Right f <- popen "nonexistent_command_for_the_test 2>/dev/null" Read
    | Left e => say ("popen: " ++ show e)
  say ("nonexistent: " ++ showE !(fRead f) ++ " " ++ show !(pclose f))
  -- writing
  fflush stdout
  Right f <- popen "tr a-z A-Z" WriteTruncate
    | Left e => say ("popen: " ++ show e)
  ignore (fPutStr f "written\n")
  say ("pclose: " ++ show !(pclose f))
  -- popen2: through the child and back
  Right p <- popen2 "while read l; do echo \"<$l>\"; done; exit 5"
    | Left e => say ("popen2: " ++ show e)
  for_ ["one", "two"] $ \w => do
    ignore (fPutStr p.input (w ++ "\n"))
    fflush p.input
    say ("echoed: " ++ showE !(fGetLine p.output))
  closeFile p.input
  say ("eof: " ++ showE !(fGetLine p.output))
  say ("popen2Wait: " ++ show !(popen2Wait p))
  closeFile p.output
  -- the process id is the one of the command: signals reach it, with their
  -- default action
  Right p <- popen2 "sleep 10"
    | Left e => say ("popen2: " ++ show e)
  _ <- system ("kill -INT " ++ show p.pid)
  say ("SIGINT: " ++ show !(popen2Wait p))
  Right p <- popen2 "sleep 10"
    | Left e => say ("popen2: " ++ show e)
  _ <- system ("kill -TERM " ++ show p.pid)
  say ("SIGTERM: " ++ show !(popen2Wait p))
  -- no child is left over (a zombie, say)
  _ <- system ("ps -o stat= --ppid " ++ show !getPID ++ " | grep -c Z")
  pure ()
