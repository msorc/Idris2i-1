module GetChar

-- getChar at the end of the input: the value differs between the back ends
-- (and is not printed), but the end of the input is seen by fEOF.

import System.File

main : IO ()
main = do
  a <- getChar
  putStrLn ("first is x: " ++ show (a == 'x'))
  e <- fEOF stdin
  putStrLn ("eof after the first: " ++ show e)
  b <- getChar
  e <- fEOF stdin
  putStrLn ("eof after the end: " ++ show e)
  b <- getChar
  e <- fEOF stdin
  putStrLn ("eof after another: " ++ show e)
  Right l <- fGetLine stdin
    | Left err => putStrLn ("error " ++ show err)
  putStrLn ("line at the end: " ++ show l)
