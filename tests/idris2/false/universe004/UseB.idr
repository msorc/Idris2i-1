module UseB

import Base
import UseA

-- Code would contain itself
codeOfCode : Code
codeOfCode = MkCode Code
