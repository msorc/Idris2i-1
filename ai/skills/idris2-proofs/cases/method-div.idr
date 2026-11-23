-- expect: E0602
-- This fork: div and mod are partial methods, so a total function using them on
-- a concrete type is not covering. Fix with divNatNZ n 2 ItIsSucc.

import Data.Nat

total
half : Nat -> Nat
half n = n `div` 2
