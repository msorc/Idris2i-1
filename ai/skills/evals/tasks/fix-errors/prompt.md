`Report.idr` was written by a colleague who knows Haskell well and Idris not at all,
and it does not compile. Please fix it. Keep its structure and the names of its
functions; change only what has to change for Idris 2.

When it works, `idris2 Report.idr -o report && ./build/exec/report` must print exactly
what is in `expected.txt`.
