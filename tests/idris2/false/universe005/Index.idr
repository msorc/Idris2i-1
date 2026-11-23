||| The index of a data type is checked against the type of the data type's
||| argument: if it was not, T U would hold U in the universe of U.
module Index

U : Type
U = Type

data T : U -> Type where
  MkT : T U
