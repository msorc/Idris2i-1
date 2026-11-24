module F

-- A imported only under an alias, and only privately
import A as Y

public export
fval : Nat
fval = Y.f (Y.MkT 7)
