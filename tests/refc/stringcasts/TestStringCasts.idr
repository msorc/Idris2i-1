module Main

main : IO ()
main = do
  printLn (cast {to = Bits8}   "42")
  printLn (cast {to = Bits16}  "4242")
  printLn (cast {to = Bits32}  "424242")
  printLn (cast {to = Bits64}  "2000000000")
  printLn (cast {to = Int8}    "-42")
  printLn (cast {to = Int16}   "-4242")
  printLn (cast {to = Int32}   "-424242")
  printLn (cast {to = Int64}   "-2000000000")
  printLn (cast {to = Int}     "-42")
  printLn (cast {to = Integer} "-123456789012345678901234567890")
  printLn (cast {to = Nat}     "42")
  printLn (cast {to = Double}  "1.5")
  -- StrHead compiles to the head() macro, which uses the String -> Char cast
  printLn (prim__strHead "abc")
  -- The whole string is read as a number, as in the Chez backend: decimal
  -- numbers and fractions are truncated, anything else is 0, and the result
  -- wraps around.
  let inputs = ["12", "+12", "-12", "12.0", "12.7", "-12.7", ".5", "5.", "1e3",
                "-2.5e-1", "7/2", "-7/2", "12abc", "abc", "", " 12", "#x10",
                "5000000000", "-5000000000", "18446744073709551617",
                "1234567890123456789012345678901234567890"]
  printLn (map (cast {to = Integer}) inputs)
  printLn (map (cast {to = Int}) inputs)
  printLn (map (cast {to = Int32}) inputs)
  printLn (map (cast {to = Int8}) inputs)
  printLn (map (cast {to = Bits8}) inputs)
  printLn (map (cast {to = Bits64}) inputs)
  printLn (map (cast {to = Double}) inputs)
