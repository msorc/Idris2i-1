module Arrays

import Data.Linear.Array
import Data.IOArray

%default total

-- IArray is defined with IOArray, of a module that Data.Linear.Array imports
-- privately, and IOArray with ArrayData, an external type with no
-- constructors, of a module that Data.IOArray imports privately.
data Rose = Node Int (IArray Rose)

data U = MkU (IOArray U)
