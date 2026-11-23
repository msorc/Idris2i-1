module Lib

public export
pub : Nat -> Nat
pub Z = 1
pub (S k) = pub k * 2

export
abstr : Nat -> Nat
abstr x = x + 2

priv : Nat -> Nat
priv x = x + 3
