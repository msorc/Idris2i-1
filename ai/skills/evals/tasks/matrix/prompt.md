Write `Matrix.idr` (module `Matrix`, with `%default total`) for matrices whose
dimensions are in the type. `Check.idr` in this directory uses the module and must
compile unchanged; it says exactly which names and types are needed:

- `Matrix rows cols a`: `rows` rows of `cols` elements, built on `Vect`, so that a
  literal `[[1, 2, 3], [4, 5, 6]]` is a `Matrix 2 3 Integer`
- `transposeM`: rows become columns
- `mulM`: matrix product
- `identityM n`: the `n` by `n` identity
- `rowsM`, `colsM`: the dimensions as run-time numbers
- `showM`: one line per row, elements separated by one space, lines joined by `\n`

Write the functions yourself; do not use `transpose` or other matrix functions from the
library. `idris2 Check.idr -o check && ./build/exec/check` should print the results.
