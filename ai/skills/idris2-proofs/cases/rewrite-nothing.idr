-- expect: E1001
-- The goal has no n + 0 in it, so rewriting by n + 0 = n changes nothing.

import Data.Nat

same : (n : Nat) -> n = n
same n = rewrite plusZeroRightNeutral n in Refl
