||| Shifting an Integer by a count of 2^64 or more: the count was cut to its
||| low bits.  A shift right gives 0 or -1, a shift left of 0 gives 0, and
||| one of any other number is an error (there is no memory for the result;
||| the Chez backend runs out of memory).
module Main

import Data.IORef

-- (read at run time: nothing is folded)
runtime : a -> IO a
runtime x = newIORef x >>= readIORef

main : IO ()
main = do
  big <- runtime 18446744073709551617
  huge <- runtime (2 * 18446744073709551616 * 18446744073709551616 + 1)
  printLn (prim__shr_Integer 12345 big)
  printLn (prim__shr_Integer (-12345) big)
  printLn (prim__shr_Integer 123456789012345678901234567890 huge)
  printLn (prim__shr_Integer (-123456789012345678901234567890) huge)
  printLn (prim__shl_Integer 0 big)
  printLn (prim__shl_Integer 5 (negate big))
  printLn (prim__shl_Integer (-5) (negate big))
  printLn (prim__shr_Integer 0 (negate big))
  -- counts that fit still shift
  printLn (prim__shl_Integer 3 100)
  printLn (prim__shr_Integer (prim__shl_Integer 3 100) 99)
  printLn (prim__shl_Integer 1 big)
