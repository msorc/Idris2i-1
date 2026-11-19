module Main

main : IO ()
main = do
  putStrLn "Hello from chez-sep"
  printLn (sum (the (List Integer) [1 .. 100]))
