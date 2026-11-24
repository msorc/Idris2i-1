||| But a computation can't return one of its own universe: the field
||| `a` of Pure is in a universe below that of Comp. (C is one use of Comp,
||| and in the mutual block both uses of C below are the same copy of C,
||| so of Comp.)
module NestedValue

%default total

data Nat = Z | S Nat

data Comp : Type -> Type where
  Pure : a -> Comp a
  Bind : Comp a -> (a -> Comp b) -> Comp b

mutual
  C : Type -> Type
  C = Comp

  nested : C (C Nat)
  nested = Pure (Pure Z)
