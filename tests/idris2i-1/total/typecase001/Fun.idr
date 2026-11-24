-- #1116
data Fun : (Type -> Type) -> Type where

app : Type -> Type -> Type
app (Fun f) = f
app _       = \a => a

total
loop : Type
loop = app (Fun (\a => app a a)) (Fun (\a => app a a))
