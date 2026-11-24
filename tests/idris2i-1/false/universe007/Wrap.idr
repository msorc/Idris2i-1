||| A wrapper of types can hold a wrapper of types at another universe, but
||| not itself: within a mutual block, T unfolds to the same use of Wrap each
||| time
module Wrap

%default total

data Wrap : Type where
  MkWrap : Type -> Wrap

interface Pack t where
  pack : Type -> t

Pack Wrap where
  pack = MkWrap

-- a Wrap holding a Wrap (of another universe)
nested : Wrap
nested = pack Wrap

-- a Wrap holding itself (in the mutual block, both uses of T are the same
-- copy)
mutual
  T : Type
  T = Wrap

  self : T
  self = pack T
