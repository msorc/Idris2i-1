-- The Doubles that are no numbers are read back from the strings that `show`
-- writes them as: `+inf.0`, `-inf.0` and `+nan.0`, like the Chez backend
-- (whose `string->number` reads these, in any case, and nothing else: the
-- `inf`, `nan` and `Infinity` of C are 0.0, like any string that is not a
-- number).

-- The casts of the strings of a list are made when the program runs.
inputs : List String
inputs = ["+inf.0", "-inf.0", "+nan.0", "-nan.0",
          "+INF.0", "-Inf.0", "+NaN.0", "-NAN.0",
          -- not numbers
          "inf.0", "nan.0", "inf", "+inf", "-inf", "nan", "+nan", "-nan",
          "Infinity", "+Infinity", "-Infinity", "NaN", "infinity",
          "+inf.", "+inf.00", "+nan.00", "+inf.0e1", "+inf.0 ", " +inf.0",
          "++inf.0", "+inf.0\0", "+inf\x0E0", "+inf.\x10", "+KNF.0",
          "nan(1)", "+nan(1)", "0x10", "1e",
          -- numbers too big for a Double
          "1e400", "-1e400"]

roundTrip : Double -> String
roundTrip x = show x ++ " -> " ++ show (the Double (cast (show x)))

main : IO ()
main = do
  printLn (map (cast {to = Double}) inputs)
  -- what `show` writes is read back
  let zero = cast {to = Double} (cast {to = String} (the Int 0))
  traverse_ (putStrLn . roundTrip)
    [1.0 / zero, -1.0 / zero, zero / zero, sqrt (-1.0 - zero), 1.0e308 * (10.0 + zero),
     0.1 + zero, 1.0e100 + zero, -0.0 * (1.0 + zero)]
  -- the casts of literals, which the compiler may compute itself, are the same
  printLn (the Double (cast "+inf.0"), the Double (cast "-inf.0"),
           the Double (cast "+nan.0"), the Double (cast "-nan.0"))
  printLn (the Double (cast "+Inf.0"), the Double (cast "inf"),
           the Double (cast "nan"), the Double (cast "Infinity"))
  -- other types still read these as 0
  printLn (map (cast {to = Integer}) ["+inf.0", "-inf.0", "+nan.0"])
  printLn (map (cast {to = Int}) ["+inf.0", "-inf.0", "+nan.0"])
