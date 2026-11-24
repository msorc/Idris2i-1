-- negative inside a record parameter
%default total
record R a where
  constructor MkR
  get : a -> Void
data Bad : Type where
  MkBad : R Bad -> Bad
notBad : Bad -> Void
notBad (MkBad r) = r.get (MkBad r)
void : Void
void = notBad (MkBad (MkR notBad))
