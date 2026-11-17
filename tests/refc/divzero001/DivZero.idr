-- A division by zero stops the program with an error (it is undefined
-- behaviour in C, and traps on x86).  The divisor is made at run time (from
-- the number of arguments of the program), so that the compiler does not
-- fold the division.
module Main

import System

%default partial

-- (a loop on Ints, which the code generator keeps unboxed)
divLoop : Int -> Int -> Int -> Int
divLoop x d acc = if d < 0 then acc else divLoop x (d - 1) (acc + prim__div_Int x d)

modLoop : Int -> Int -> Int -> Int
modLoop x d acc = if d < 0 then acc else modLoop x (d - 1) (acc + prim__mod_Int x d)

test : String -> Integer -> String
test "Bits8" z = show (prim__div_Bits8 7 (cast z))
test "Bits16" z = show (prim__div_Bits16 7 (cast z))
test "Bits32" z = show (prim__div_Bits32 7 (cast z))
test "Bits64" z = show (prim__div_Bits64 7 (cast z))
test "Int8" z = show (prim__div_Int8 7 (cast z))
test "Int16" z = show (prim__div_Int16 7 (cast z))
test "Int32" z = show (prim__div_Int32 7 (cast z))
test "Int64" z = show (prim__div_Int64 7 (cast z))
test "Int" z = show (prim__div_Int 7 (cast z))
test "Integer" z = show (prim__div_Integer 7 z)
test "big Integer" z = show (prim__div_Integer 100000000000000000000000 z)
test "mod Bits8" z = show (prim__mod_Bits8 7 (cast z))
test "mod Bits16" z = show (prim__mod_Bits16 7 (cast z))
test "mod Bits32" z = show (prim__mod_Bits32 7 (cast z))
test "mod Bits64" z = show (prim__mod_Bits64 7 (cast z))
test "mod Int8" z = show (prim__mod_Int8 7 (cast z))
test "mod Int16" z = show (prim__mod_Int16 7 (cast z))
test "mod Int32" z = show (prim__mod_Int32 7 (cast z))
test "mod Int64" z = show (prim__mod_Int64 7 (cast z))
test "mod Int" z = show (prim__mod_Int 7 (cast z))
test "mod Integer" z = show (prim__mod_Integer 7 z)
test "mod big Integer" z = show (prim__mod_Integer 100000000000000000000000 z)
test "loop" z = show (divLoop 7 (cast z + 3) 0)
test "mod loop" z = show (modLoop 7 (cast z + 3) 0)
test _ _ = "?"

main : IO ()
main = do
  (_ :: w :: _) <- getArgs
    | _ => putStrLn "an argument please"
  -- 0, with one argument
  z <- (\args => cast (length args) - 2) <$> getArgs
  putStrLn (assert_total (test w z))
