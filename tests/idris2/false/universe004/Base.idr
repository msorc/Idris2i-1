module Base

public export
data Code : Type where
  MkCode : Type -> Code

public export
decode : Code -> Type
decode (MkCode t) = t
