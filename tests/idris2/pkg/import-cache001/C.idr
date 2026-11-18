module C

import A as X
import B

public export
c : Nat
c = X.f (X.MkT 3) +++ A.f (MkT 4) +++ h
