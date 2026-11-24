||| A heterogeneous list containing heterogeneous lists
module HList

%default total

private infixr 7 ::

data Nat = Z | S Nat

data List : Type -> Type where
  Nil : List a
  (::) : a -> List a -> List a

data HList : List Type -> Type where
  HNil : HList []
  HCons : t -> HList ts -> HList (t :: ts)

inner : HList [Nat, Nat]
inner = HCons Z (HCons (S Z) HNil)

outer : HList [HList [Nat, Nat], Nat]
outer = HCons inner (HCons Z HNil)

deeper : HList [HList [HList [Nat, Nat], Nat]]
deeper = HCons outer HNil
