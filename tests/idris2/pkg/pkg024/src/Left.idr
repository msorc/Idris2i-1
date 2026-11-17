module Left

import Base

export
twice : Colour -> Colour
twice c = next (next c)
