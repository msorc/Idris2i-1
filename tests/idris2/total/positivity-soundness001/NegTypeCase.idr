-- type-case on the argument itself
%default total
H : Type -> Type
H Nat = Nat
H a = a -> Void
record R a where
  constructor MkR
  get : H a
data Bad : Type where
  MkBad : R Bad -> Bad
