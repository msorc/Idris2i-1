libc : String -> String
libc fn = "C:" ++ fn ++ ",libc"

-- Not a list of specifiers: an application of `libc "abs"`, as anywhere else
%foreign (libc "abs") (libc "abs")
absF : Int -> Int
