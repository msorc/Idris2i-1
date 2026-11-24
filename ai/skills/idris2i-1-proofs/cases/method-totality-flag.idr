-- expect: ok
-- Without total (and without --method-totality) div is accepted in a covering function.

import Data.Nat

half : Nat -> Nat
half n = n `div` 2
