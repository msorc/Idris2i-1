module Lib

public export
pub : Nat -> Nat
pub x = x + 1

export
abstr : Nat -> Nat
abstr x = x + 2

priv : Nat -> Nat
priv x = x + 3

export
usesPriv : Nat -> Nat
usesPriv x = priv x
