-- negative occurrence via parameter of another type
%default total
data NegT : Type -> Type where
  MkNeg : (a -> Void) -> NegT a

data Bad : Type where
  MkBad : NegT Bad -> Bad

notBad : Bad -> Void
notBad (MkBad (MkNeg f)) = f (MkBad (MkNeg f))

void : Void
void = notBad (MkBad (MkNeg notBad))
