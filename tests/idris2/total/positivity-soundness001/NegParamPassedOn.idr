-- parameter passed on to a negative use inside another parameterised type
%default total
data NegT : Type -> Type where
  MkNegT : (a -> Void) -> NegT a
data Wrap : Type -> Type where
  MkWrap : NegT a -> Wrap a
data Bad : Type where
  MkBad : Wrap Bad -> Bad
notBad : Bad -> Void
notBad (MkBad (MkWrap (MkNegT f))) = f (MkBad (MkWrap (MkNegT f)))
void : Void
void = notBad (MkBad (MkWrap (MkNegT notBad)))
