-- legitimate nested and parameterised types that must stay accepted
%default total
data Vect' : Nat -> Type -> Type where
  VNil : Vect' Z a
  VCons : a -> Vect' n a -> Vect' (S n) a
data Rose a = Node a (List (Rose a))
data Tree = Leaf | Br (Nat -> Tree)
data T2 = MkT2 (Maybe (List T2)) (Pair T2 Nat)
data Ex2 = MkEx2 (n : Nat ** Vect' n Ex2)
data Ex3 = MkEx3 (DPair Nat (\n => Vect' n Ex3))
data Strm = SCons Nat (Inf Strm)
record Pt a where
  constructor MkPt
  x : a
data UsesPt = MkU (Pt UsesPt)
data UsesEither = L (Either UsesEither Nat)
data UsesFn = MkFn (Nat -> List UsesFn)
