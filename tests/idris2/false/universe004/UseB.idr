module UseB

import Base
import UseA

-- C would contain itself (the constraints of C come from Base's TTC file)
codeOfCode : C
codeOfCode = MkCode C
