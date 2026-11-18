-- type-level function using a case block
%default total
G : Bool -> Type -> Type
G b a = case b of
          True => a -> Void
          False => a
record R (b : Bool) a where
  constructor MkR
  get : G b a
data Bad : Type where
  MkBad : R True Bad -> Bad
notBad : Bad -> Void
notBad (MkBad r) = r.get (MkBad r)
void : Void
void = notBad (MkBad (MkR notBad))
