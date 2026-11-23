-- expect: E0201
main : IO ()
main = do
  contents <- readFile "input.txt"
  pure ()
