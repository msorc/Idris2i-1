module NegB

-- NegA is imported privately: a module that imports only NegB does not load
-- it, so it cannot look at the constructors of NegT.
import NegA

public export
data W a = MkW (NegT a)

export
mk : (a -> Void) -> W a
mk f = MkW (MkNegT f)

export
un : W a -> a -> Void
un (MkW (MkNegT f)) = f
