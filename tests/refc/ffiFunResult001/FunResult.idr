-- C cannot give Idris a function: the RefC backend reports it, rather than
-- generating C that calls a function that does not exist.

%foreign "C:getTwice,libfun,fun.h"
prim__getTwice : PrimIO (Int -> Int)

main : IO ()
main = do
  f <- primIO prim__getTwice
  printLn (f 21)
