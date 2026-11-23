||| A definition is a copy at each use: `T` below stands for `Type` at
||| another universe each time, as `Type` does, so a `T` can hold a `T`,
||| as `Type b : Type a` with `b < a` (Coq accepts the same).
module Levels

%default total

data Nat = Z | S Nat

data Both : Type -> Type -> Type where
  MkBoth : a -> b -> Both a b

T : Type
T = Type

x : T
x = T

-- T at two universes in one definition
both : Both T T
both = MkBoth Nat T

-- a type of types through T
Pred : T -> T
Pred a = a -> T
