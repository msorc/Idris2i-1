module Main

-- A branch that matches several cells of the same constructor keeps them
-- all for the constructors that it builds, when they are unique: the merge
-- of two lists takes over both cons cells, and `count` takes over the cell
-- of the pair that the recursive call returns as well as the cons cell.

merge : List Int -> List Int -> List Int
merge [] ys = ys
merge xs [] = xs
merge (x :: xs) (y :: ys)
    = if x < y then x :: merge xs (y :: ys)
               else y :: merge (x :: xs) ys

-- (the pair and the cons cell have the same constructor to RefC)
count : List Int -> (Int, List Int)
count [] = (0, [])
count (x :: xs) = let (n, xs') = count xs in (n + 1, x :: xs')

-- two cells matched, one built: the other one is freed
firstOfTwo : List Int -> List Int -> List Int
firstOfTwo (x :: _) (y :: ys) = (x + y) :: ys
firstOfTwo xs _ = xs

-- a branch that builds fewer cells than the other keeps fewer
pick : Bool -> List Int -> List Int -> List Int
pick b (x :: xs) (y :: ys) = if b then x :: y :: xs else [x + y]
pick _ _ _ = []

main : IO ()
main = do
  printLn (merge [1, 4, 6, 9] [2, 3, 7, 8, 10])
  let shared = [5, 6, 7]
  -- the cells of `shared` have other references: they are not taken over
  printLn (merge shared [1, 8], shared)
  printLn (count [3, 1, 2])
  printLn (firstOfTwo [1, 2] [10, 20, 30])
  printLn (pick True [1, 2] [3, 4], pick False [1, 2] [3, 4])
  printLn (pick True shared shared, shared)
