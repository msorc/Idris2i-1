module Main

-- getLine until the end of the input: under Valgrind, the number of blocks
-- lost may not grow with the number of lines (the support library gave each
-- line in a buffer from malloc, which the Scheme backends copied and never
-- freed).

readLines : Nat -> Nat -> IO (Nat, Nat)
readLines n len = do
  l <- getLine
  if l == ""
     then pure (n, len)
     else readLines (S n) (len + length l)

main : IO ()
main = do
  first <- getLine
  printLn first
  printLn !(readLines 0 0)
  -- at the end of the input, the line is empty
  printLn !getLine
