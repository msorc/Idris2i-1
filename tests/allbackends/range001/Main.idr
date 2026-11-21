module Main

-- Ranges with a step, `[x, y .. z]`, of every type that has one, in both
-- directions, with a step that goes past `z`, and ending at the ends of the
-- types of fixed width, where the next step wraps around.  A step down from a
-- small `Nat` stops at zero.

-- The largest Int, found by the step where it wraps around (the bounds of
-- Int differ between back ends)
largest : Int -> Int
largest x = let y = 2 * x + 1 in if y > x then largest y else x

main : IO ()
main = do
  putStrLn "Nat"
  printLn [the Nat 10, 9 .. 0]
  printLn [the Nat 4, 2 .. 0]
  printLn [the Nat 5, 3 .. 0]
  printLn [the Nat 5, 3 .. 1]
  printLn [the Nat 7, 4 .. 2]
  printLn [the Nat 2, 1 .. 0]
  printLn [the Nat 1, 0 .. 0]
  printLn [the Nat 0, 1 .. 3]
  printLn [the Nat 1, 3 .. 8]
  printLn [the Nat 3, 5 .. 1]
  printLn [the Nat 3, 1 .. 5]
  printLn [the Nat 3, 3 .. 3]
  printLn [the Nat 3, 3 .. 4]
  printLn [the Nat 10 .. 0]
  printLn [the Nat 0 .. 3]

  putStrLn "Integer"
  printLn [the Integer 10, 7 .. 0]
  printLn [the Integer 10, 7 .. (-5)]
  printLn [the Integer (-3), (-1) .. 4]
  printLn [the Integer 1, 3 .. 0]
  printLn [the Integer 1, (-1) .. 2]
  printLn [the Integer 2, 2 .. 2]
  printLn [the Integer 2, 2 .. 3]

  putStrLn "Int"
  printLn [the Int 10, 9 .. 0]
  printLn [the Int 10, 7 .. (-5)]
  printLn [the Int (-3), (-1) .. 4]
  printLn [the Int 1, 3 .. 0]
  -- (only how the elements relate to the bounds is shown)
  let m = largest 1
  let l = - m - 1
  printLn ([m - 2, m - 1 .. m] == [m - 2, m - 1, m])
  printLn ([m - 3, m - 1 .. m] == [m - 3, m - 1])
  printLn ([m - 1, m .. m] == [m - 1, m])
  printLn ([l + 2, l + 1 .. l] == [l + 2, l + 1, l])
  printLn ([l + 3, l + 1 .. l] == [l + 3, l + 1])
  printLn ([l, 0 .. m] == [l, 0])
  printLn ([m, 0 .. l] == [m, 0, l + 1])

  putStrLn "Int8"
  printLn [the Int8 125, 126 .. 127]
  printLn [the Int8 124, 126 .. 127]
  printLn [the Int8 126, 127 .. 127]
  printLn [the Int8 (-126), (-127) .. (-128)]
  printLn [the Int8 (-125), (-127) .. (-128)]
  printLn [the Int8 (-128), 0 .. 127]
  printLn [the Int8 (-128), 127 .. 127]
  printLn [the Int8 127, (-128) .. (-128)]
  printLn [the Int8 127, 0 .. (-128)]
  printLn [the Int8 (-128), (-64) .. 127]
  printLn [the Int8 0, 100 .. 127]

  putStrLn "Int16, Int32, Int64"
  printLn [the Int16 32765, 32766 .. 32767]
  printLn [the Int16 (-32768), 0 .. 32767]
  printLn [the Int32 2147483645, 2147483646 .. 2147483647]
  printLn [the Int32 (-2147483648), 0 .. 2147483647]
  printLn [the Int64 9223372036854775805, 9223372036854775806 .. 9223372036854775807]
  printLn [the Int64 9223372036854775806, 9223372036854775807 .. 9223372036854775807]
  printLn [the Int64 (-9223372036854775806), (-9223372036854775807) .. (-9223372036854775807 - 1)]
  printLn [the Int64 (-9223372036854775807 - 1), 0 .. 9223372036854775807]
  printLn [the Int64 9223372036854775807, 0 .. (-9223372036854775807 - 1)]

  putStrLn "Bits"
  printLn [the Bits8 253, 254 .. 255]
  printLn [the Bits8 0, 200 .. 255]
  printLn [the Bits8 2, 1 .. 0]
  printLn [the Bits8 5, 3 .. 0]
  printLn [the Bits8 255, 0 .. 0]
  printLn [the Bits16 65533, 65534 .. 65535]
  printLn [the Bits32 4294967293, 4294967294 .. 4294967295]
  printLn [the Bits64 18446744073709551613, 18446744073709551614 .. 18446744073709551615]
  printLn [the Bits64 0, 10000000000000000000 .. 18446744073709551615]
  printLn [the Bits64 2, 1 .. 0]

  putStrLn "Char"
  printLn ['a', 'c' .. 'i']
  printLn ['i', 'f' .. 'a']
