-- Arithmetic on the fixed-width integers where the result is close to
-- a power of two: the Chez back end has a fast path for the results that
-- are small enough.

main : IO ()
main = do
  -- Int has 64 bits (the limit of a fixnum of Chez is 2^60)
  printLn (the Int 1152921504606846975 + 1)
  printLn (the Int 1152921504606846976 + 1152921504606846976)
  printLn (the Int (-1152921504606846976) - 1)
  printLn (the Int 4611686018427387904 * 2)
  printLn (the Int 9223372036854775807 + 1)
  printLn (the Int (-9223372036854775808) - 1)
  printLn (the Int 3037000500 * 3037000500)
  printLn (the Int 100000 * 100000)
  -- the smaller signed types wrap sooner
  printLn (the Int8 127 + 1)
  printLn (the Int16 (-32768) - 1)
  printLn (the Int32 2147483647 + 1)
  printLn (the Int64 9223372036854775807 + 1)
  printLn (the Int64 1152921504606846976 + 1152921504606846976)
  -- the unsigned types
  printLn (the Bits8 255 + 1)
  printLn (the Bits32 4294967295 + 1)
  printLn (the Bits64 18446744073709551615 + 1)
  printLn (the Bits64 1152921504606846976 * 16)
  printLn (the Bits64 1152921504606846975 + 1)
  printLn (the Bits64 5 - 6)
  printLn (the Bits64 4294967296 * 4294967296)
  -- the casts to Bits64
  printLn (cast {to = Bits64} (the Int (-1)))
  printLn (cast {to = Bits64} (the Int 5))
  printLn (cast {to = Bits64} (the Int 1152921504606846976))
  printLn (cast {to = Bits64} (the Int (-9223372036854775808)))
