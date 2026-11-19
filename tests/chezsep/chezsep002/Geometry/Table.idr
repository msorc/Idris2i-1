module Geometry.Table

-- from contrib
import Data.SortedMap

import Data.List
import Geometry.Shape

export
areas : List Shape -> SortedMap String Nat
areas = foldl (\m, s => insertWith (+) (name s) (area s) m) empty
  where
    insertWith : (Nat -> Nat -> Nat) -> String -> Nat -> SortedMap String Nat ->
                 SortedMap String Nat
    insertWith f k v m = case lookup k m of
                           Nothing => insert k v m
                           Just o => insert k (f o v) m

export
grandTotal : SortedMap String Nat -> Nat
grandTotal m = sum (map snd (SortedMap.toList m))
