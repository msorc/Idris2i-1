-- upstream #2297: positivity through a partially applied type function
%default total
Rel : Type -> Type
Rel a = (x, y : a) -> Type
Pred : Type -> Type
Pred a = a -> Type
private infixl 5 :<
data Bwd : Rel a -> Rel a where
  BNil : Bwd r i i
  (:<) : Bwd r i j -> r j k -> Bwd r i k
Kleisli : Pred Type -> Rel Type
Kleisli m a b = a -> m b
data Free : Pred Type -> Pred Type where
  Pure : a -> Free m a
  Bind : m a -> Bwd (Kleisli (Free m)) a b -> Free m b
