-- Variant B of mergeInt: owned style.  `OList` stands for a type the planned
-- `[owned]` checker would accept: its recursive field has quantity 1 and every
-- function takes and returns it at quantity 1, so no OList value is ever
-- duplicated or dropped.  The comparison is `x < y` on Int, as in variant A.
--
-- Uniqueness at run time: every OList cell is made by `gen` (or rebuilt from a
-- cell that was just matched), the result of `gen` is passed straight to
-- `msort` and from there to `mylast` (no let binding at quantity omega, no
-- top-level constant of type OList), and every function consumes its OList
-- arguments exactly once, so each cell has exactly one reference.
module Main

data OList : Type where
  Nil  : OList
  Cons : Int -> (1 _ : OList) -> OList

gen : Int -> Int -> OList
gen 0 n = Nil
gen k n = let n' = (1103515245 * n + 12345) `mod` 2147483648 in
              Cons n' (gen (k - 1) n')

reverseOnto : (1 acc : OList) -> (1 _ : OList) -> OList
reverseOnto acc Nil = acc
reverseOnto acc (Cons x xs) = reverseOnto (Cons x acc) xs

reverse : (1 _ : OList) -> OList
reverse xs = reverseOnto Nil xs

-- the length, reading the list without consuming it: the list is handed back
-- in a `Res` (this is the idiom the plan's phase 4 is to make free)
len : (1 _ : OList) -> Res Int (const OList)
len Nil = 0 # Nil
len (Cons x xs) = let (n # xs') = len xs in (n + 1) # Cons x xs'

merge : (1 _ : OList) -> (1 _ : OList) -> OList
merge Nil         right       = right
merge left        Nil         = left
merge (Cons x xs) (Cons y ys) =
  case x < y of
       True  => Cons x (merge xs (Cons y ys))
       False => Cons y (merge (Cons x xs) ys)

-- splitRec of Data.List without the hare: it takes k elements, k = length / 2
-- (the original's hare walks floor (length / 2) steps), and returns the same
-- pair (rest, front)
splitRec : Int -> (1 _ : OList) -> (1 zs : OList) -> LPair OList OList
splitRec 0 ys          zs = ys # reverse zs
splitRec k Nil         zs = Nil # reverse zs
splitRec k (Cons y ys) zs = splitRec (k - 1) ys (Cons y zs)

-- the original's two cases [] and [x] become a test of the length
msort : (1 _ : OList) -> OList
msort xs =
  let (n # xs') = len xs in
  case n < 2 of
       True  => xs'
       False => let (x # y) = splitRec (n `div` 2) xs' Nil in
                    merge (msort (assert_smaller xs x)) (msort (assert_smaller xs y))

mylast : (1 _ : OList) -> Maybe Int
mylast Nil = Nothing
mylast (Cons x Nil) = Just x
mylast (Cons x xs) = mylast xs

doSort : Int -> IO ()
doSort 0 = putStrLn "Done"
doSort k = do putStrLn $ show $ mylast (msort (gen 12000 (k - 1)))
              doSort (k - 1)

main : IO ()
main = do max <- getLine
          doSort (cast max)
