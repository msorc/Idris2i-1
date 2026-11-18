-- negative via a lambda in a parameter of a user type
%default total
data Ex : (Nat -> Type) -> Type where
  MkEx : (n : Nat) -> p n -> Ex p
data Bad : Type where
  MkBad : Ex (\_ => Bad -> Void) -> Bad
notBad : Bad -> Void
notBad (MkBad (MkEx n f)) = f (MkBad (MkEx n f))
void : Void
void = notBad (MkBad (MkEx Z notBad))
