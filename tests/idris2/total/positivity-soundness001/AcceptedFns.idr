-- positive stuck type-level functions must stay accepted (cf. libs/papers Data.W)
%default total
data Sh = Z0 | One | Two Sh Sh
Arr : Sh -> Type -> Type
Arr Z0 r = ()
Arr One r = r
Arr (Two d e) r = (Arr d r, Arr e r)
private infixr 0 ~>
record (~>) (d : Sh) (r : Type) where
  constructor MkArr
  runArr : Arr d r
data W : (sh : Type) -> (pos : sh -> Sh) -> Type where
  MkW : (s : sh) -> (pos s ~> W sh pos) -> W sh pos
K : Bool -> Type -> Type
K b a = case b of
          True => List a
          False => Maybe a
record RK (b : Bool) a where
  constructor MkRK
  get : K b a
data UsesK = MkUK (RK True UsesK)
