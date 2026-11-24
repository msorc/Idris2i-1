module Lib
%default total
public export
data NegT : Type -> Type where
  MkNegT : (a -> Void) -> NegT a
export
data Hidden : Type -> Type where
  MkHidden : (a -> Void) -> Hidden a
export
mkHidden : (a -> Void) -> Hidden a
mkHidden = MkHidden
export
useHidden : Hidden a -> a -> Void
useHidden (MkHidden f) = f
