||| With --debug-spec-collide, every copy of `pick` has the same key, as two
||| copies by different arguments may have otherwise: the copy of `pick P` in A
||| and that of `pick Q` in B used to have the same name, and Main called one
||| of them for both.  The copies of a module are in a namespace of its own.
module Main

import A
import B
import Base

main : IO ()
main = do
  printLn (useA 0)
  printLn (useB 0)
  printLn (useBP 0)
  printLn (pick R 0)
  printLn (pick Q 0)
  printLn (pick P 0)
