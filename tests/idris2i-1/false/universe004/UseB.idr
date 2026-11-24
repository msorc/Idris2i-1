module UseB

import Base
import UseA

-- In the mutual block, both uses of C' are the same copy of Code, which
-- would contain itself (the constraints of Code come from Base's TTC file)
mutual
  C' : Type
  C' = Code

  codeOfCode : C'
  codeOfCode = MkCode C'
