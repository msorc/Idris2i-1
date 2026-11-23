||| The index of a data type is checked against the type of the data type's
||| argument: if it was not, T U would hold U in the universe of U. (In the
||| mutual block, both uses of U are the same copy of U.)
module Index

mutual
  U : Type
  U = Type

  data T : U -> Type where
    MkT : T U
