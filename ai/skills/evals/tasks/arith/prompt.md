`Arith.idr` (package `arith.ipkg`, which depends on `base` and `contrib`) states six
facts about natural numbers and four functions on `Vect`, and leaves each as a hole.
Fill them in: real proofs for the facts, working definitions for the functions (the
comments say what each returns). You may add helper lemmas and imports, but do not
change `sumTo`, `sumSquares` or the ten signatures, and keep `%default total`.

No `believe_me`, `assert_total`, `assert_smaller`, `idris_crash` or `partial`.
`idris2i-1 --typecheck arith.ipkg` must succeed with no holes left.
