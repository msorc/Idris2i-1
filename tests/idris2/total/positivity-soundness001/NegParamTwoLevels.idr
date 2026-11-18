-- negative via two levels of parameters
%default total
data NegT : Type -> Type where
  MkNegT : (a -> Void) -> NegT a
data Box : Type -> Type where
  MkBox : a -> Box a
data Bad : Type where
  MkBad : Box (NegT Bad) -> Bad
notBad : Bad -> Void
notBad (MkBad (MkBox (MkNegT f))) = f (MkBad (MkBox (MkNegT f)))
void : Void
void = notBad (MkBad (MkBox (MkNegT notBad)))
