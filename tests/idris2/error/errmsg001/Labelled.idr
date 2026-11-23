-- The expected and the actual type differ from the two types that do not
-- match: both pairs are shown, the outer one labelled
data Vect : Nat -> Type -> Type where
  Nil : Vect Z a
  (::) : a -> Vect k a -> Vect (S k) a

f : Vect n a -> Vect (S n) a
f xs = xs
