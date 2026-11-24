import System

f : Nat -> Nat
f n = ?todo

main : IO ()
main = do args <- getArgs
          if length args > 5
             then printLn (f 3)
             else putStrLn "with a hole"
