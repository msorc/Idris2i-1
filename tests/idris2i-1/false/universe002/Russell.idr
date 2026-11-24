||| The type of all "sets": a data type containing a type of its own size
module Russell

data Set : Type where
  Sup : (a : Type) -> (a -> Set) -> Set

-- Set is in the universe of its field `a : Type`, so it can't be one
setOfAll : Set
setOfAll = Sup Set id
