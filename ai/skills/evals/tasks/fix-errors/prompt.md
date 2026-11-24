`Report.idr` was written by a colleague who knows Haskell well and Idris2i-1 not at all,
and it does not compile. Please fix it. Keep its structure and the names of its
functions; change only what has to change for Idris2i-1.

When it works, `idris2i-1 Report.idr -o report && ./build/exec/report` must print exactly
what is in `expected.txt`.
