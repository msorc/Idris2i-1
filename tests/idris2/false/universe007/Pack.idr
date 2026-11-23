||| The universes of the fields of a data type depend on the use (they are
||| polymorphic), but a use records them, so an implementation of an
||| interface which stores a type can't be used to make a type contain
||| itself: `pack Set id` needs the Set given to `pack` and the Set made to
||| be the same.
module Pack

%default total

id : a -> a
id x = x

data Set : Type where
  Sup : (a : Type) -> (a -> Set) -> Set

interface Pack t where
  pack : (a : Type) -> (a -> t) -> t

Pack Set where
  pack = Sup

setOfAll : Set
setOfAll = pack Set id
