module Pipes

-- popen, popen2, pclose, run and runProcessingOutput on Node: the output is
-- that of Chez and RefC.

import Data.List
import Data.String
import System
import System.File

%default covering

say : String -> IO ()
say = putStrLn

showE : Show a => Either FileError a -> String
showE (Left e) = "Left " ++ show e
showE (Right x) = "Right " ++ show x

-- popen for reading: the output, in pieces, and the exit code
readers : IO ()
readers = do
  Right f <- popen "echo one; echo two; exit 3" Read
    | Left e => say ("popen: " ++ show e)
  say ("line: " ++ showE !(fGetLine f))
  say ("char: " ++ showE !(fGetChar f))
  say ("rest: " ++ showE !(fRead f))
  say ("eof: " ++ show !(fEOF f))
  say ("pclose: " ++ show !(pclose f))
  -- a lot of output, more than a pipe holds
  Right f <- popen "seq 1 100000" Read
    | Left e => say ("popen: " ++ show e)
  Right all <- fRead f
    | Left e => say ("fRead: " ++ show e)
  say ("seq: " ++ show (length (lines all)) ++ " lines, " ++ show (length (unpack all)) ++ " characters")
  say ("pclose: " ++ show !(pclose f))
  -- the command that does not exist
  Right f <- popen "nonexistent_command_for_the_test 2>/dev/null" Read
    | Left e => say ("popen: " ++ show e)
  say ("nonexistent: " ++ showE !(fRead f))
  say ("pclose: " ++ show !(pclose f))
  -- the output of the command arrives while it still runs
  Right f <- popen "echo first; sleep 1; echo second" Read
    | Left e => say ("popen: " ++ show e)
  say ("first: " ++ showE !(fGetLine f))
  say ("second: " ++ showE !(fGetLine f))
  say ("end: " ++ showE !(fGetLine f))
  say ("pclose: " ++ show !(pclose f))

-- run and runProcessingOutput
runners : IO ()
runners = do
  say (show !(run (the String "echo hello; echo there; exit 2")))
  say (show !(run (the String "true")))
  say (show !(run (the String "printf 'no newline'")))
  code <- runProcessingOutput (\l => say ("got " ++ show l)) (the String "printf 'a\\nb\\n\\nlast'; exit 5")
  say ("code " ++ show code)
  say (show !(run ["printf", "%s|%s", "x y", "it's"]))

-- popen for writing: the command's output is ours
writers : IO ()
writers = do
  say "before"
  fflush stdout
  Right f <- popen "tr a-z A-Z; echo done" WriteTruncate
    | Left e => say ("popen: " ++ show e)
  Right () <- fPutStr f "hello\nworld\n"
    | Left e => say ("fPutStr: " ++ show e)
  say ("pclose: " ++ show !(pclose f))
  fflush stdout
  say "after"

-- popen2
both : IO ()
both = do
  Right p <- popen2 "cat; echo end; exit 4"
    | Left e => say ("popen2: " ++ show e)
  say ("pid: " ++ show (p.pid > 0))
  -- lines go through the child one at a time
  for_ ["alpha", "beta", "gamma"] $ \w => do
    Right () <- fPutStr p.input (w ++ "\n")
      | Left e => say ("fPutStr: " ++ show e)
    fflush p.input
    say ("echoed: " ++ showE !(fGetLine p.output))
  closeFile p.input
  say ("rest: " ++ showE !(fRead p.output))
  say ("eof: " ++ show !(fEOF p.output))
  say ("popen2Wait: " ++ show !(popen2Wait p))
  closeFile p.output
  -- a megabyte in, a number out
  Right p <- popen2 "wc -c"
    | Left e => say ("popen2: " ++ show e)
  let chunk = fastPack (replicate 1024 'x')
  for_ [1 .. 1024] $ \_ => ignore (fPutStr p.input chunk)
  closeFile p.input
  say ("wc: " ++ showE !(fGetLine p.output))
  say ("popen2Wait: " ++ show !(popen2Wait p))
  -- two at the same time
  Right p1 <- popen2 "cat"
    | Left e => say ("popen2: " ++ show e)
  Right p2 <- popen2 "while read l; do echo \"p2:$l\"; done"
    | Left e => say ("popen2: " ++ show e)
  _ <- fPutStr p1.input "one\n"
  _ <- fPutStr p2.input "two\n"
  fflush p1.input
  fflush p2.input
  say ("p2: " ++ showE !(fGetLine p2.output))
  say ("p1: " ++ showE !(fGetLine p1.output))
  -- (the second child holds the first one's pipe too in C: end it first)
  closeFile p2.input
  w2 <- popen2Wait p2
  closeFile p1.input
  w1 <- popen2Wait p1
  say ("waits: " ++ show (w2, w1))
  -- a command that exits at once, and the program reads from it
  Right p <- popen2 "exit 7"
    | Left e => say ("popen2: " ++ show e)
  closeFile p.input
  say ("empty: " ++ showE !(fGetLine p.output))
  say ("popen2Wait: " ++ show !(popen2Wait p))

-- the child reads the stdin of the program
inheritors : IO ()
inheritors = do
  Right f <- popen "cat" Read
    | Left e => say ("popen: " ++ show e)
  say ("cat: " ++ showE !(fRead f))
  say ("pclose: " ++ show !(pclose f))

main : IO ()
main = do
  args <- getArgs
  case drop 1 args of
       ["readers"] => readers
       ["runners"] => runners
       ["writers"] => writers
       ["both"] => both
       ["stdin"] => inheritors
       _ => do readers; runners; writers; both
