module Main

import Data.List
import Data.String.Iterator

-- Each fold over a string makes an iterator (an offset into the string, with
-- nothing to free): no value may leak.
countA : String -> Nat
countA = Data.String.Iterator.foldl (\n, c => if c == 'a' then S n else n) 0

main : IO ()
main = do
  printLn (sum (map (\i => countA ("banana " ++ show i)) [1 .. the Nat 10000]))
