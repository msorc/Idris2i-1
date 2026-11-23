module Main

-- the flags of the C compiler and of the linker that pkg-config gives for bar
%cg refc refc-pkg-config=bar

%foreign "C:bar_inc,,bar.h"
prim__barInc : Int -> Int

main : IO ()
main = printLn (prim__barInc 41)
