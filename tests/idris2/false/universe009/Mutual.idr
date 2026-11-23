||| The definitions of a mutual block are one group: they refer to each
||| other at the group's own universes, so `T : T` is rejected there.
module Mutual

%default total

mutual
  T : Type
  T = Type

  selfT : T
  selfT = T
