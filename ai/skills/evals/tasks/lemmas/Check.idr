module Check

import Lemmas

%default total

-- The definitions must be the original ones.
revDef : rev [1, 2, 3] = the (List Nat) [3, 2, 1]
revDef = Refl

sumDef : sumList [1, 2, 3] = 6
sumDef = Refl

c1 : (xs, ys : List a) -> rev (xs ++ ys) = rev ys ++ rev xs
c1 = revAppend

c2 : (xs : List a) -> rev (rev xs) = xs
c2 = revInvolutive

c3 : (f : a -> b) -> (xs : List a) -> map f (rev xs) = rev (map f xs)
c3 = mapRev

c4 : (xs, ys : List Nat) -> sumList (xs ++ ys) = sumList xs + sumList ys
c4 = sumAppend

c5 : (xs : List Nat) -> sumList (rev xs) = sumList xs
c5 = sumRev
