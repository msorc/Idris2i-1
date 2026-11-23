||| An implementation of an interface is a definition like any other: each
||| use of it is a copy, whose universes can differ from those of another
||| use. Here `Applicative Elab` is used for a computation returning a
||| record whose field takes an Applicative implementation, and elsewhere as
||| that very field: with one copy of the implementation for both, its
||| universes would have to be above and below those of the record.
module Derive

%default total

data Nat = Z | S Nat

interface Applicative (0 f : Type -> Type) where
  pure : a -> f a
  map : (a -> b) -> f a -> f b

record Trav (0 t : Type -> Type) where
  constructor MkTrav
  trav : {0 a, b : Type} -> {0 g : Type -> Type} -> Applicative g =>
         (a -> g b) -> t a -> g (t b)

data Elab : Type -> Type where
  Pure : a -> Elab a

Applicative Elab where
  pure = Pure
  map f (Pure x) = Pure (f x)

data Id : Type -> Type where
  MkId : a -> Id a

idTrav : Trav Id
idTrav = MkTrav (\ f, x => case x of MkId y => map MkId (f y))

-- Elab's pure at the type of a record holding Applicative implementations
derive : Elab (Trav Id)
derive = pure idTrav

-- Elab's Applicative given to the record's field
useElab : Trav Id -> Elab (Id Nat)
useElab tr = trav tr (\ n => pure n) (MkId Z)
