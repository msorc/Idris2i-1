`Syntax.idr` has the syntax of a small language. The checker I am writing has to decide
equality on all of it: add `DecEq` implementations for `Ty`, `Op`, `Term n`, `Rose` and
`Pos` to this file.

They must be total: keep `%default total`, and use no `believe_me`, `assert_total`,
`assert_smaller`, `idris_crash`, `partial` or `covering`. Do not change the data
declarations. `idris2i-1 --check Syntax.idr` must succeed.
