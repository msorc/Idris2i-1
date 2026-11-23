-- expect: ok
-- The fix for W0007: compute the value once with `let` and pass it to the helper.
-- `idris2 -Wwhere-recompute --check` reports nothing here.

countBig : List Int -> Int
countBig xs = let big = foldl (+) 0 xs `div` 2 in go big xs 0
  where
    go : Int -> List Int -> Int -> Int
    go b [] acc = acc
    go b (y :: ys) acc = go b ys (if y * 1000 > b then acc + 1 else acc)
