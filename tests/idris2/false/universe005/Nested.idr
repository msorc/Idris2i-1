||| The index of a data type can be in a bigger universe than the fields of
||| the constructors: an index is not stored. So a computation returning a
||| computation has a type, as for the `Elab` monad of the reflection library.
module Nested

%default total

data Nat = Z | S Nat

data Comp : Type -> Type where
  Pure : a -> Comp a
  Bind : Comp a -> (a -> Comp b) -> Comp b

-- The type Comp (Comp Nat) exists (but has no values made with Pure or
-- Bind, see NestedValue)
same : Comp (Comp Nat) -> Comp (Comp Nat)
same x = x

data Box : Type -> Type where
  MkBox : (0 t : Type) -> Box t

boxed : Box (Comp (Comp Nat))
boxed = MkBox (Comp (Comp Nat))
