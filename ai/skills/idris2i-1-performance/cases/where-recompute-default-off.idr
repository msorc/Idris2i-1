-- expect: ok
-- W0007 (a local definition without arguments, recomputed at each use) is off by
-- default: this file has the bug and checks without a warning. With
-- `idris2i-1 -Wwhere-recompute --check` it reports W0007 at `big`.

countBig : List Int -> Int
countBig xs = go xs 0
  where
    big : Int
    big = foldl (+) 0 xs `div` 2
    go : List Int -> Int -> Int
    go [] acc = acc
    go (y :: ys) acc = go ys (if y * 1000 > big then acc + 1 else acc)
