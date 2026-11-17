module Hdr

-- a macro of include/scale.h, which uses one of include/factor.h
%foreign "C:stamp_scale,libc,scale.h"
scale : Int -> Int

main : IO ()
main = printLn (scale 21)
