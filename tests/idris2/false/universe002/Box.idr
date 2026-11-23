||| A data type is no smaller than the universe of its parameters: a list of
||| types can't be put where a small type is needed. (The list type is
||| defined here: the prelude of the test suite is not universe-checked.)
module Box

data Small : Type where
  MkSmall : (a : Type) -> a -> Small

data Seq : Type -> Type where
  Nil : Seq a
  (::) : a -> Seq a -> Seq a

data Wrap : Type where
  MkWrap : Seq Small -> Wrap

-- Wrap holds a list of Smalls, so it is at least as big as Small: this is
-- accepted, as the Smalls in Wrap are of another copy of Small than the one
-- holding Wrap
wrapSmall : Small
wrapSmall = MkSmall Wrap (MkWrap [])

-- S is one copy of Small: a list of S can't be held by S
S : Type
S = Small

seqSmall : S
seqSmall = MkSmall (Seq S) []
