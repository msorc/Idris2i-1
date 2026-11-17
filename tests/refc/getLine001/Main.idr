module Main

import Data.List

-- getLine, many times: under Valgrind, no line may be lost (each one was,
-- when the line from the support library was copied and not freed).

readLines : Nat -> List String -> IO (List String)
readLines 0 acc = pure (reverse acc)
readLines (S k) acc = do l <- getLine
                         readLines k (l :: acc)

main : IO ()
main = do
  n <- getLine
  ls <- readLines (cast (the Integer (cast n))) []
  printLn (length ls)
  traverse_ (\l => printLn (l, length l)) (take 4 ls)
  printLn (last' ls)
  printLn (sum (map length ls))
  -- at the end of the input, the line is empty
  printLn !getLine
  printLn !getLine
