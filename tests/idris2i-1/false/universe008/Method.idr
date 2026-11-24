||| The type of a method's type variable is inferred by unification, here
||| as the very universe of the domain of `f` (`empty : f a`), although
||| `f a` only needs it to be no bigger. Each binder whose type is a
||| universe gets one of its own, so an implementation can store the
||| method's type variable in a data type whose index universe is above its
||| own universe (as `Join` puts Elab's).
module Method

%default covering

interface Empty (0 f : Type -> Type) where
  empty : f a

data Comp : Type -> Type where
  Pure : a -> Comp a
  Fail : Comp a
  Join : Comp (Comp a) -> Comp a

Empty Comp where
  empty = Fail
