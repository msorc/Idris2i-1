module NoRecompute

import Data.List

-- None of these warn.

expensive : Nat -> List Nat
expensive m = [0 .. m]

-- A constant which uses none of the enclosing variables
constant : List Nat -> Nat
constant xs = sum (map go xs)
  where
    us : List Nat
    us = expensive 100

    go : Nat -> Nat
    go x = if elem x us then x else 0

-- A local function with arguments of its own
withArgs : Nat -> List Nat -> Nat
withArgs m xs = sum (map go xs)
  where
    go : Nat -> Nat
    go x = if elem x (expensive m) then x else 0

-- A local constant used once, outside any lambda or local function
once : Nat -> Nat
once m = sum us
  where
    us : List Nat
    us = expensive m

-- Uses only an erased variable of the enclosing definition
erasedOnly : {0 a : Type} -> List a -> Nat
erasedOnly xs = sum (map go xs)
  where
    none : List a
    none = []

    go : a -> Nat
    go x = length none

-- Passed on explicitly: the recommended fix
shared : Nat -> List Nat -> Nat
shared m xs = let us = expensive m in sum (map (go us) xs)
  where
    go : List Nat -> Nat -> Nat
    go us x = if elem x us then x else 0
