||| The shape of `Libraries.Data.WithData.AddMetadata`: matching on a type
||| `WithData ls a` takes out `ls`, a list of pairs holding types, at the copy
||| of the type given at run time. The check puts every universe in the type
||| of `ls` no lower than the universe `w` of the argument, so the types in
||| `ls` would be in `w`, and `WithData ls a` (above its parameter, which holds
||| them) above `w`. The types in a run time `ls` are only strictly below `w`,
||| so a checker with constraints of the form `w <= u + 1` could accept this;
||| this one has no such constraints, and rejects it.
module TypeMatch

%default total

private infixr 7 ::

data List : Type -> Type where
  Nil : List a
  (::) : a -> List a -> List a

record KeyVal where
  constructor MkKeyVal
  key : String
  ty : Type

-- values of the types of a list of pairs (Record in the compiler)
data Values : List KeyVal -> Type where
  VNil : Values []
  VCons : {0 kv : KeyVal} -> ty kv -> Values ls -> Values (kv :: ls)

record WithData (ls : List KeyVal) (payload : Type) where
  constructor MkWithData
  metadata : Values ls
  val : payload

AddMetadata : KeyVal -> Type -> Type
AddMetadata lbl (WithData ls a) = WithData (lbl :: ls) a
AddMetadata lbl ty = WithData [lbl] ty
