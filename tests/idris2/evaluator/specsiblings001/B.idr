module B

import Base

export
%noinline
useB : Int -> Int
useB n = pick Q n

-- the copy that A makes too
export
%noinline
useBP : Int -> Int
useBP n = pick P n
