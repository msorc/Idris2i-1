-- recursive type-level function, negative only in its base case
%default total
F : Nat -> Type -> Type
F Z a = a -> Void
F (S n) a = F n a
record R (n : Nat) a where
  constructor MkR
  get : F n a
data Bad : Type where
  MkBad : R 3 Bad -> Bad
notBad : Bad -> Void
notBad (MkBad r) = r.get (MkBad r)
void : Void
void = notBad (MkBad (MkR notBad))
