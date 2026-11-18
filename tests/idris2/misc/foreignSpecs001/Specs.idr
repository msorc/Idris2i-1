-- On one line, a string literal followed by more expressions is a list of
-- specifiers: the literal, then the specifiers of the rest of the line.

libc : String -> String
libc fn = "C:" ++ fn ++ ",libc"

-- a literal, then a computed specifier in parentheses
%foreign "scheme:abs" (libc "abs")
absA : Int -> Int

-- a literal, then an application without parentheses
%foreign "scheme:abs" libc "abs"
absB : Int -> Int

-- several literals and an interpolated string
%foreign "javascript:lambda:x=>Math.abs(x)" "scheme:\{"abs"}" (libc "abs")
absC : Int -> Int

-- one specifier per line, as before
%foreign (libc "abs")
         "scheme:abs"
absD : Int -> Int

-- a single computed specifier, as before
%foreign libc "abs"
absE : Int -> Int

main : IO ()
main = printLn [absA (-1), absB (-2), absC (-3), absD (-4), absE (-5)]
