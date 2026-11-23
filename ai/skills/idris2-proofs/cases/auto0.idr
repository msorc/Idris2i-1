-- expect: ok
-- An auto 0 proof is found by the caller's proof search and erased.

import Data.Nat

pos : (n : Nat) -> {auto 0 ok : LTE 1 n} -> Nat
pos n = n

three : Nat
three = pos 3
