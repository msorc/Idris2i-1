module Recompute

import Data.List

-- Local definitions without arguments of their own which use the enclosing
-- definition's variables are recomputed at each use. All of these warn.

expensive : Nat -> List Nat
expensive m = [0 .. m]

-- Used from a local function with arguments
sumLookups : Nat -> List Nat -> Nat
sumLookups m xs = sum (map go xs)
  where
    us : List Nat
    us = expensive m

    go : Nat -> Nat
    go x = if elem x us then x else 0

-- Used under a lambda
countIn : Nat -> List Nat -> Nat
countIn m xs = length (filter (\x => elem x us) xs)
  where
    us : List Nat
    us = expensive m

-- Used twice
twice : Nat -> Nat
twice m = length us + sum us
  where
    us : List Nat
    us = expensive m

-- Local definitions in a `let` block are lifted in the same way
letBlock : Nat -> List Nat -> List Nat
letBlock m xs
  = let us : List Nat
        us = expensive m
        keep : Nat -> Bool
        keep x = elem x us
    in filter keep xs

-- Used from a case block
inCase : Nat -> List Nat -> Nat
inCase m xs = sum (map (\x => case x of
                                   Z => length us
                                   S k => k) xs)
  where
    us : List Nat
    us = expensive m
