-- No data type needed: the pattern (Type -> p) binds p : Type -> Type.
app : Type -> Type -> Type
app (Type -> p) = p
app _ = \a => a

total
loop : Type
loop = app ((x : Type) -> app x x) ((x : Type) -> app x x)

-- The domain may turn out to be Type later.
total
cod : (t : Type) -> Type
cod (a -> p) = (x : a) -> p x
cod t = t
