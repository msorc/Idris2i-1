-- record parameter used through a stuck type-level function, negative in one clause
%default total
T : Bool -> Type -> Type
T True a = a -> Void
T False a = a
record R (b : Bool) a where
  constructor MkR
  get : T b a
data Bad : Type where
  MkBad : R True Bad -> Bad
notBad : Bad -> Void
notBad (MkBad r) = r.get (MkBad r)
void : Void
void = notBad (MkBad (MkR notBad))
