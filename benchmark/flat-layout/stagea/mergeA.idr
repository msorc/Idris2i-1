-- Variant A of mergeInt: the original algorithm (Data.List.sortBy, mergeBy and
-- splitRec, copied) on `List Int`, with the `Ord` dictionary specialised away
-- by hand: the comparison is `x < y` on Int.  The input is made by a plain
-- recursive function instead of `take size (lincong seed)` on a Stream of
-- Integer, so that A and B make their input the same way (same numbers: they
-- stay below 2^31 and the product below 2^62).
module Main

gen : Int -> Int -> List Int
gen 0 n = []
gen k n = let n' = (1103515245 * n + 12345) `mod` 2147483648 in
              n' :: gen (k - 1) n'

-- Data.List.mergeBy with order = compare, specialised to Int
merge : List Int -> List Int -> List Int
merge []      right   = right
merge left    []      = left
merge (x::xs) (y::ys) =
  case x < y of
       True  => x :: merge xs (y::ys)
       False => y :: merge (x::xs) ys

-- Data.List.sortBy's split, unchanged (the list is walked twice: as the hare
-- and as the tortoise)
splitRec : List Int -> List Int -> List Int -> (List Int, List Int)
splitRec (_::_::xs) (y::ys) zs = splitRec xs ys (y :: zs)
splitRec _          ys      zs = (ys, reverse zs)

msort : List Int -> List Int
msort []  = []
msort [x] = [x]
msort xs  = let (x, y) = splitRec xs xs [] in
    merge (msort (assert_smaller xs x)) (msort (assert_smaller xs y))

mylast : List Int -> Maybe Int
mylast [] = Nothing
mylast [x] = Just x
mylast (x::xs) = mylast xs

doSort : Int -> IO ()
doSort 0 = putStrLn "Done"
doSort k = do let xs = msort $ gen 12000 (k - 1)
              putStrLn $ show $ mylast xs
              doSort (k - 1)

main : IO ()
main = do max <- getLine
          doSort (cast max)
