||| The same, matching on a function type (the pattern binds `b` as a
||| function from Unit)
module Cod

%default total

data Unit = MkUnit

cod : Type -> Type
cod (Unit -> b) = b MkUnit
cod _ = Unit

T : Type
T = cod (Unit -> Type)

selfT : T
selfT = T
