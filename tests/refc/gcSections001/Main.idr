module Main

-- A program that uses little of the runtime: no casts, no Double, no
-- threads of its own.
main : IO ()
main = do putStrLn "hello"
          printLn (the Int 6 * 7)
