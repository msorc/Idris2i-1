-- A value with more references than its 16-bit count can hold: the extra
-- ones are counted on the side, and the value is freed once they are gone
-- (it used to become immortal).
import System
import Data.List
import System.Concurrency

total' : List String -> Nat
total' = foldl (\n, s => n + length s) 0

main : IO ()
main = do
  args <- getArgs
  -- (made at run time, so that it is not a constant)
  let v = show (70000 + length args)
  let xs = replicate 70000 v
  printLn (total' xs)
  -- and shared between threads, which take references at the same time
  t1 <- fork $ do
    pure ()
    printLn (total' (replicate 70000 v))
  t2 <- fork $ do
    pure ()
    printLn (total' (replicate 70000 v))
  threadWait t1
  threadWait t2
  putStrLn v
