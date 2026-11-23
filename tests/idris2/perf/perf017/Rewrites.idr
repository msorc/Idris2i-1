module Rewrites

import Data.Nat

%default total

-- A chain of rewrites, from `multOneSoleNeutral` in Data.Nat.Factor (contrib).
-- Each `rewrite` binds its predicate and its rule with a let, and each
-- implementation of `Num Nat` that search finds below them was a definition
-- under all those lets.  Applying the transformation rules of `+` and `*`
-- normalised such definitions with the lets kept, which made terms that grew
-- elevenfold with each rewrite: checking this took more than three minutes
-- and 4 GB.
lem : (k, j : Nat) -> S (S k) = S (S k) * S (S j) ->
      k + 0 = k + (S j + S (j + (k * S j)))
lem k j prf =
        rewrite plusSuccRightSucc j (S (j + (k * S j))) in
        rewrite plusZeroRightNeutral k in
        rewrite plusAssociative k j (S (S (j + (k * S j)))) in
        rewrite sym $ plusCommutative j k in
        rewrite sym $ plusAssociative j k (S (S (j + (k * S j)))) in
        rewrite sym $ plusSuccRightSucc k (S (j + (k * S j))) in
        rewrite sym $ plusSuccRightSucc k (j + (k * S j)) in
        rewrite plusAssociative k j (k * S j) in
        rewrite plusCommutative k j in
        rewrite sym $ plusAssociative j k (k * S j) in
        rewrite sym $ multRightSuccPlus k (S j) in
        injective $ injective prf
