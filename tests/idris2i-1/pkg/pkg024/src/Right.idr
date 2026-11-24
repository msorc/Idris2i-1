module Right

import Base

export
thrice : Colour -> Colour
thrice c = next (next (next c))

export
isRed : Colour -> Bool
isRed Red = True
isRed _ = False
