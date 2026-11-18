module NegE

import NegD

%default total

data Bad = MkBad (V Bad)

notBad : Bad -> Void
notBad (MkBad v) = unV v (MkBad v)

boom : Void
boom = notBad (MkBad (mkV notBad))
