||| Key types whose hash function is deliberately bad, and a test helper.
module Keys

import Data.Hashable

%default total

-- Every key has the same hash.
public export
record Same where
  constructor MkSame
  n : Int

export
Eq Same where
  a == b = a.n == b.n

export
Show Same where
  show x = "Same " ++ show x.n

export
Hashable Same where
  hashWithSalt s _ = s

-- Only seven different hashes.
public export
record Few where
  constructor MkFew
  n : Int

export
Eq Few where
  a == b = a.n == b.n

export
Show Few where
  show x = "Few " ++ show x.n

export
Hashable Few where
  hashWithSalt s x = hashWithSalt s (x.n `mod` 7)

-- Hashes that differ in the high bits (of the 30 that the maps use) and in the
-- two lowest, so that the tries are as deep as they get.
public export
record High where
  constructor MkHigh
  n : Int

export
Eq High where
  a == b = a.n == b.n

export
Show High where
  show x = "High " ++ show x.n

export
Hashable High where
  hashWithSalt _ x = cast (x.n `mod` 32) * 0x2000000 + cast (x.n `mod` 3)


||| Print the name of a check and whether it passed.
export
check : String -> Bool -> IO ()
check name ok = putStrLn (name ++ ": " ++ if ok then "ok" else "FAILED")

||| The list `[0, 1, .. n - 1]`, built without deep recursion (the JavaScript
||| back ends have a small stack).
export
upTo : Int -> List Int
upTo n = go (integerToNat (cast n)) (n - 1) []
  where
    go : Nat -> Int -> List Int -> List Int
    go Z _ acc = acc
    go (S k) i acc = go k (i - 1) (i :: acc)
