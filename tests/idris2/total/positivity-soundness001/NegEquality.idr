%default total
data D : Type where Abs : (D = e) -> (e -> Void) -> D
lam : (D -> Void) -> D
lam f = Abs Refl f
app : D -> D -> Void
app (Abs Refl f) d = f d
omega : D
omega = lam (\x => app x x)
Omega : Void
Omega = app omega omega
