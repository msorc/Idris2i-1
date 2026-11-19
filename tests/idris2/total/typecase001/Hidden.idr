%default total

-- The function over types is hidden in a record.
record Pred where
  constructor MkPred
  holds : Type -> Bool

data I : Pred -> Type where

J : Type -> Type -> Bool
J (I p) = holds p
J _ = \_ => True

-- ... or behind a type variable that another function looks at.
data Tag : (a : Type) -> a -> Type where

use : (a : Type) -> a -> Type -> Bool
use (Type -> Bool) f = f
use _ _ = \_ => True

K : Type -> Type -> Bool
K (Tag a x) = use a x
K _ = \_ => True

-- ... or in a case block.
L : Type -> Type -> Bool
L t = case t of
           I p => holds p
           _ => \_ => True

-- A caller is not total either.
viaJ : Bool
viaJ = J Nat Nat
