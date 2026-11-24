You are in a git worktree of the Idris2i-1 compiler fork, at the tip of its `devel`
branch. Do not build the compiler here. A compiler built from this very commit is
at `REPO/build/exec/idris2i-1`, the libraries it tests against are in `REPO/build/env`,
and the built test runner is `REPO/tests/build/exec/runtests`. Treat `REPO` as
read-only.

Add a golden test to the suite that pins down this behaviour: interpolating a `Nat`
in a string (`"count: \{n}"` with `n : Nat`) is rejected with the error
`Can't find an implementation for Interpolation Nat`, and the same definition with
`\{show n}` is accepted.

Put the test where a test like this belongs, follow the conventions of its
neighbours, and make sure it passes when the suite runs it. Leave the worktree ready
to commit, without committing.
