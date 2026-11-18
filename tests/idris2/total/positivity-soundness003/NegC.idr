module NegC

import NegB

%default total

-- W uses its parameter negatively (through NegT, which this module does not
-- see): Bad must be rejected, or it proves Void.
data Bad = MkBad (W Bad)

notBad : Bad -> Void
notBad (MkBad w) = un w (MkBad w)

boom : Void
boom = notBad (MkBad (mk notBad))
