-- expect: E0101
-- After an expression that is not a string literal, the rest of the line is
-- its arguments: this is `(libc "labs") "scheme:abs"`, an application of a
-- String.  Put each such specifier on a line of its own.

libc : String -> String
libc fn = "C:" ++ fn ++ ",libc,stdlib.h"

%foreign (libc "labs") "scheme:abs"
cabs : Int -> Int
