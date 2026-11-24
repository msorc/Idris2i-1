||| The shape of `Deriving.*.derive` (`EitherT` over `Elab`) and of
||| `Control.Linear.LIO`: a monad whose bind is a constructor hides the
||| intermediate type `a` in a field, strictly below the monad's own universe.
||| A transformer over it stores an `m (...)` and binds through `m`'s bind at
||| a type which contains that very `m` (the same copy: the transformer's
||| dictionary is made for one `m`), so `m`'s bind would hold a value of its
||| own universe. Not typeable predicatively.
module Transformer

%default total

data Nat = Z | S Nat

interface Monad (0 m : Type -> Type) where
  pure : a -> m a
  bind : m a -> (a -> m b) -> m b

data M : Type -> Type where
  Pure : a -> M a
  Bind : M a -> (a -> M b) -> M b

Monad M where
  pure = Pure
  bind = Bind

record T (0 m : Type -> Type) (a : Type) where
  constructor MkT
  run : m a

Monad m => Monad (T m) where
  pure x = MkT (pure x)
  bind (MkT x) f = MkT (bind x (\ y => run (f y)))

-- join through T's bind: m's bind at the type `T m a`, which holds an `m`
joinT : Monad m => T m (T m a) -> T m a
joinT x = bind x (\ y => y)

nested : T M Nat
nested = joinT (pure (pure Z))
