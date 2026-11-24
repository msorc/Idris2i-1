-- What makes an implementation, or a function using one, not covering is
-- recorded in the TTC of its module, which was checked without
-- --method-totality
module Use

import Lib

%default total

direct : T -> T
direct = foo

indirect : T -> T
indirect = useFoo
