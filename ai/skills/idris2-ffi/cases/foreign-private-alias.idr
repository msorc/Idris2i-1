-- expect: E0000
-- "Can't marshal type for foreign call Main.N.Handle": a type alias in a
-- namespace block is private, and is not unfolded when the foreign type is
-- read.  Make it `public export`.

namespace N
  Handle : Type
  Handle = AnyPtr

  %foreign "C:malloc,libc,stdlib.h"
  prim__alloc : Int -> PrimIO Handle
