||| The definitions lifted out of a definition (local definitions, case
||| blocks, with blocks) are one group with it: they refer to each other at
||| the group's own universes, so these are one copy, and `T : T` is
||| rejected there.
module Group

%default total

outer : Type
outer = T
  where
    T : Type
    T = Type

    selfT : T
    selfT = T
