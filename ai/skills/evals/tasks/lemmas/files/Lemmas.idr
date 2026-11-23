module Lemmas

%default total

||| Reverse, the simple way.
public export
rev : List a -> List a
rev [] = []
rev (x :: xs) = rev xs ++ [x]

||| Sum of a list of naturals.
public export
sumList : List Nat -> Nat
sumList [] = 0
sumList (x :: xs) = x + sumList xs

export
revAppend : (xs, ys : List a) -> rev (xs ++ ys) = rev ys ++ rev xs
revAppend xs ys = ?revAppend_rhs

export
revInvolutive : (xs : List a) -> rev (rev xs) = xs
revInvolutive xs = ?revInvolutive_rhs

export
mapRev : (f : a -> b) -> (xs : List a) -> map f (rev xs) = rev (map f xs)
mapRev f xs = ?mapRev_rhs

export
sumAppend : (xs, ys : List Nat) -> sumList (xs ++ ys) = sumList xs + sumList ys
sumAppend xs ys = ?sumAppend_rhs

export
sumRev : (xs : List Nat) -> sumList (rev xs) = sumList xs
sumRev xs = ?sumRev_rhs
