`Util.idr` works (see `Check.idr`, which prints what is in `expected.txt`), but none of
its functions is accepted as total. I want to add `%default total` to the module.

Make every function in `Util.idr` total for real: no `assert_total`, `assert_smaller`,
`believe_me`, `idris_crash`, and no `partial` or `covering` annotations. You may rewrite
the bodies and add helpers, proofs or implicit arguments to the signatures, as long as
`Check.idr` compiles unchanged and still prints `expected.txt`.

`chunksOf 0 xs` loops today. Decide what a total version should do with a zero length
and say so in the documentation comment; rejecting it in the type is fine too.
