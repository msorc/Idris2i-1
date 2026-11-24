module NegD

-- Through NegB, imported privately: NegT is two private imports away from a
-- module that imports only this one.
import NegB

public export
data V a = MkV (W a)

export
mkV : (a -> Void) -> V a
mkV f = MkV (mk f)

export
unV : V a -> a -> Void
unV (MkV w) = un w
