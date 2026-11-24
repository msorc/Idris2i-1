||| Ordinary code which uses types as values is accepted. It needs the
||| definitions to be polymorphic in their universes. (Everything is defined
||| here, without the prelude: the prelude of the test suite is not
||| universe-checked, so its definitions are monomorphic.)
module Ok

%default total

private infixr 7 ::

data Nat = Z | S Nat

data Bool = False | True

data Seq : Type -> Type where
  Nil : Seq a
  (::) : a -> Seq a -> Seq a

data Pair : Type -> Type -> Type where
  MkPair : a -> b -> Pair a b

data DPair : (a : Type) -> (a -> Type) -> Type where
  MkDPair : (x : a) -> p x -> DPair a p

id : a -> a
id x = x

compose : (b -> c) -> (a -> b) -> a -> c
compose f g x = f (g x)

map : (a -> b) -> Seq a -> Seq b
map f [] = []
map f (x :: xs) = f x :: map f xs

types : Seq Type
types = [Nat, Bool, Seq Nat]

nested : Seq (Seq Type)
nested = [types, [Type]]

seqs : Seq (Seq Nat)
seqs = [[Z]]

seqTypes : Seq Type
seqTypes = [Seq Nat, Type, Seq Type]

idType : Type
idType = id (id Type)

pairOfTypes : Pair Type (Seq Type)
pairOfTypes = MkPair Nat [Type]

dep : DPair Type (\ a => a)
dep = MkDPair Nat Z

mapped : Seq Type
mapped = map Seq [Nat, Bool]

SeqSeq : Type -> Type
SeqSeq = compose Seq Seq

composed : Seq Nat -> Seq (Seq Nat)
composed = compose (\ x => [x]) id

record Box where
  constructor MkBox
  ty : Type
  val : ty

boxes : Seq Box
boxes = [MkBox Nat Z, MkBox (Seq Type) [Nat]]

unbox : Box -> Type
unbox b = b.ty
