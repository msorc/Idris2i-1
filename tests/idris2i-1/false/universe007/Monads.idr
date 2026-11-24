||| Two implementations of an interface at different universes: the methods
||| of `Monad Id` can be used at a type of computations of `Comp`, whose
||| fields are above those of Id's uses here
module Monads

%default total

data Nat = Z | S Nat

interface Monad (0 m : Type -> Type) where
  pure : a -> m a
  bind : m a -> (a -> m b) -> m b

data Id : Type -> Type where
  MkId : a -> Id a

Monad Id where
  pure = MkId
  bind (MkId x) f = f x

data Comp : Type -> Type where
  Pure : a -> Comp a
  Bind : Comp a -> (a -> Comp b) -> Comp b

Monad Comp where
  pure = Pure
  bind = Bind

-- Id at the type of a computation
plan : Id (Comp Nat)
plan = pure (bind (pure Z) (\ n => pure (S n)))

run : Comp Nat -> Nat
run (Pure x) = x
run (Bind c f) = Z

result : Id Nat
result = bind plan (\ c => pure (run c))
