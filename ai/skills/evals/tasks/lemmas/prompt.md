`Lemmas.idr` states five lemmas about `rev` and `sumList` and leaves each as a hole.
Prove them: replace the holes with real proofs. You may add helper lemmas and imports,
but do not change `rev`, `sumList` or the five statements, and keep `%default total`.

No `believe_me`, `assert_total`, `assert_smaller`, `idris_crash` or `partial`.
`idris2i-1 --check Lemmas.idr` must succeed with no holes left.
