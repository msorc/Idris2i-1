-- recursive function that makes its argument negative on recursion
%default total
F : Nat -> Type -> Type
F Z a = a
F (S n) a = F n (a -> Void)
record R (n : Nat) a where
  constructor MkR
  get : F n a
data Bad : Type where
  MkBad : R 1 Bad -> Bad
notBad : Bad -> Void
notBad (MkBad r) = r.get (MkBad r)
void : Void
void = notBad (MkBad (MkR notBad))
