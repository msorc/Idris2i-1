module Libraries.Text.Distance.Levenshtein

import Data.String

%default total

||| Self-evidently correct but O(3 ^ (min mn)) complexity
spec : String -> String -> Nat
spec a b = loop (fastUnpack a) (fastUnpack b) where

  loop : List Char -> List Char -> Nat
  loop [] ys = length ys -- deletions
  loop xs [] = length xs -- insertions
  loop (x :: xs) (y :: ys)
    = if x == y then loop xs ys -- match
      else 1 + minimum
           [ loop (x :: xs) ys -- insert y
           , loop xs (y :: ys) -- delete x
           , loop xs ys        -- substitute y for x
           ]

-- Here we change Levenshtein slightly so that we may only substitute
-- alpha / numerical characters for similar ones. This avoids suggesting
-- "#" as a replacement for an out of scope "n".
substCost : Char -> Char -> Int
substCost c d
  = if c == d then 0 else
    if isAlpha c && isAlpha d then 1 else
    if isDigit c && isDigit d then 1 else 2

-- Dynamic programming, one row at a time. Row j holds the distances between
-- each prefix of `a` (of size 0 to |a|) and the prefix of `b` of size j.
-- Given row (j-1) and the j-th character `d` of `b`, `nextRow` computes the
-- cells 1 to |a| of row j:
-- * `left` is the cell (i-1) of row j
-- * `diag` is the cell (i-1) of row (j-1)
-- * the head of the last argument is the cell i of row (j-1)
-- * the head of the list of characters is the i-th character of `a`
nextRow : (d : Char) -> (left, diag : Int) -> List Char -> List Int -> List Int
nextRow d left diag (c :: cs) (up :: ups)
  = let here = min (min (left + 1)            -- delete c
                        (up + 1))             -- insert d
                   (diag + substCost c d)     -- equal or substitute d for c
    in here :: nextRow d here up cs ups
nextRow _ _ _ _ _ = []

lastCell : List Int -> Int
lastCell [x] = x
lastCell (_ :: xs) = lastCell xs
lastCell [] = 0 -- impossible: rows are never empty

-- Process the remaining characters of `b`, given the row of the previous
-- prefix of `b`. Gives up as soon as every cell of a row is above `bound`:
-- the cells of the following rows can only be larger.
rows : (bound : Int) -> List Char -> (j : Int) -> (prev : List Int) ->
       List Char -> Maybe Int
rows bound as j prev [] = Just (lastCell prev)
rows bound as j [] (_ :: _) = Nothing -- impossible: rows are never empty
rows bound as j (p :: ps) (d :: ds)
  = let row = j :: nextRow d j p as ps in
    if foldl min j row > bound then Nothing
    else rows bound as (j + 1) row ds

-- The distance between `a` (given as its characters and their number) and
-- `b`, if it is at most `bound`.
withinChars : (bound : Int) -> (as : List Char) -> (w : Int) -> String ->
              Maybe Int
withinChars bound as w b
  = do let h = cast {to = Int} (length b)
       -- Every insertion or deletion costs 1, and substitutions do not change
       -- the length, so the distance is at least the difference of lengths
       guard (abs (w - h) <= bound)
       -- (the ranges of Int use no method of Integral Int, so not its
       -- partial div and mod)
       d <- rows bound as 1 (assert_total [0..w]) (fastUnpack b)
       guard (d <= bound)
       pure d

||| The distance between two strings
export
distance : String -> String -> Nat
distance a b
  = let w = cast {to = Int} (length a)
        h = cast {to = Int} (length b) in
    -- No distance is larger than deleting all of a and inserting all of b
    maybe 0 (integerToNat . cast) $ withinChars (w + h) (fastUnpack a) w b

||| Dynamic programming
export
compute : HasIO io => String -> String -> io Nat
compute a b = pure (distance a b)

||| A string we measure the distance to many others from: its characters are
||| only computed once.
export
record Target where
  constructor MkTarget
  chars : List Char
  size : Int

export
target : String -> Target
target str = MkTarget (fastUnpack str) (cast (length str))

||| `withinDistance k a b` is `Just (distance a b)` if this distance is at most
||| `k`, and `Nothing` otherwise. It is much cheaper than `distance` when `k`
||| is small: most strings are too long or too short to be within the
||| distance, and the computation stops as soon as the distance is known to
||| exceed `k`.
export
withinDistance : (bound : Nat) -> Target -> String -> Maybe Nat
withinDistance bound (MkTarget as w) b
  = integerToNat . cast <$> withinChars (cast bound) as w b
