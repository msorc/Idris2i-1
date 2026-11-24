-- expect: E0802
-- An auto-bound implicit (n) is erased, so it cannot be returned.

import Data.Vect

len : Vect n a -> Nat
len _ = n
