module Stdin

-- getLine, getChar and the System.File functions on stdin read it as on the
-- other backends: getLine drops the line terminator, all of them share the
-- input, and the end of the input is seen by fEOF and stays.
import System.File

loop : Nat -> IO ()
loop 0 = pure ()
loop (S k) = do
  e <- fEOF stdin
  if e then putStrLn "EOF" else do
    l <- getLine
    printLn l
    loop k

main : IO ()
main = do
  c <- getChar
  printLn c
  Right l <- fGetLine stdin | Left e => printLn e
  printLn l
  Right c <- fGetChar stdin | Left e => printLn e
  printLn c
  Right s <- fGetChars stdin 3 | Left e => printLn e
  printLn s
  loop 10
  l <- getLine
  printLn l
  c <- getChar
  printLn (ord c == 0xFFFF)
