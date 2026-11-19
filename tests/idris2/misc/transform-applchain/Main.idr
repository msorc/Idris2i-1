import Rules

main : IO ()
main = do
  putStrLn inside
  putStrLn (describe (the Int 2))
  printLn (scale [the Int 1, 2])
  printLn (pairUp 1 [2, 3])
  printLn !(getAll (\x => if x > 0 then Just (x * 2) else Nothing) [1, 2, 3])
  printLn !(getAll (\x => if x > 1 then Just x else Nothing) [1, 2, 3])
