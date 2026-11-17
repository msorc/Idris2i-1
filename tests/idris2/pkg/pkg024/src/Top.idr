module Top

import Base
import Left
import Right
import Extra

export
same : Colour -> Bool
same c = isRed (thrice (twice (twice c))) == isRed (next c)
