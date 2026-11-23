---
name: idris2-compiler-dev
description: "Use when working on the Idris 2 compiler itself in this repository: editing `src/`, `libs/` or `support/`, building or bootstrapping, adding or running golden tests (`make test only=`), error messages and codes, CHANGELOG_NEXT, lint, TTC versions, commit style. Load before any change to compiler sources, the libraries shipped with it, the C support code or `tests/`, and before benchmarking a compiler change, accepting changed `expected` files, or building in a tree that other agents share."
---

# Working on the Idris 2 compiler

Everything in this skill is about the compiler repository: a fork of Idris 2
far ahead of upstream 0.8 (branch `devel`; `main` tracks upstream). Paths are
relative to the root of the checkout. `make help` is the source of truth for
targets and knobs; this file tells you which ones to use and why.

Read the reference files when the task needs them:

- `references/build.md`: every make target and variable, how the compiler
  builds itself, bootstrapping, building in a worktree, the test prefix.
- `references/tests.md`: the golden test layout, pools, `testutils.sh`,
  writing and regenerating `expected`, which groups need which tools.
- `references/traps.md`: mistakes that have cost rebuilds or false results,
  each with its symptom. Read it before benchmarking, before building
  outside `make`, and when a result looks too good or too bad.

## Map of the tree

| Path | What is there |
|---|---|
| `src/Core` | TT, the core language: terms, context, unification (`Core.Unify`), normalisation, coverage, termination, TTC serialisation (`Core.Binary`, `Core.TTC`), the `Error` type (`Core.Core`) |
| `src/TTImp` | the implicit core language and its elaborator (`TTImp.Elab.*`, `ProcessDef`, `ProcessData`, elaborator reflection) |
| `src/Idris` | the surface language: parser, desugarer, REPL, IDE mode, the build driver (`ModTree`, `ProcessIdr`, `Package`), error text (`Idris.Error`), error codes (`Idris.ErrorCode`), command line (`Idris.CommandLine`) |
| `src/Compiler` | back ends after type checking: `CompileExpr`, `Inline`, `Opts/*`, `ANF`, `RefC/*` (the default code generator), `Scheme/*` (Chez, Racket, Gambit), `ES/*` (Node, JavaScript) |
| `src/Libraries` | the compiler's own copies of data structures and utilities |
| `libs/*` | `prelude`, `base`, `linear`, `network`, `contrib`, `test` (the golden test library), `papers`, `http`, `tls`, `http-tls`; `libs/api` holds API snapshots |
| `support/c` | C support library (`libidris2_support`) that every back end links |
| `support/refc` | the RefC runtime: values, reference counting, threads, the reactor |
| `support/chez`, `support/racket`, `support/js` | the Scheme and JavaScript support code |
| `tests/` | golden tests: `tests/<group>/<category>/<name>/` with `run` and `expected` |
| `docs/source` | the Sphinx manual; `implementation/` for compiler internals, `reference/error-codes.rst`, `backends/` |
| `bootstrap/`, `bootstrap-*.sh` | generated C and Scheme of an older compiler, to build without an Idris 2 |
| `CHANGELOG_NEXT.md`, `ROADMAP.md` | unreleased changes; known gaps |

`docs/source/implementation/overview.rst` explains the term representation
and where things live in more depth.

## Before the first build

The compiler is built by another Idris 2, `IDRIS2_BOOT` (default `idris2` on
`PATH`). `idris2` is often not on `PATH` for an agent; the installed one is
usually `~/.idris2/bin/idris2`. Check:

```sh
command -v idris2 || ls ~/.idris2/bin/idris2
git log -1 --oneline          # which commit you are on
build/exec/idris2 --version   # which commit the built compiler came from
```

Pass the boot compiler on every `make` that builds: `make idris2-exec
IDRIS2_BOOT=$HOME/.idris2/bin/idris2`, or put `IDRIS2_BOOT=...` in
`custom.mk` (gitignored, included by `config.mk`).

If another agent may build or test in the same checkout, do not work there:
make a git worktree from `devel` and build in it (`references/build.md`,
"Building in a separate tree"). Two builds in one tree overwrite each
other's compiler, libraries and `tests/**/output` files.

## The edit, build, test loop

```sh
make idris2-exec IDRIS2_BOOT=$HOME/.idris2/bin/idris2   # compiler only
make libs                                               # libraries, with build/exec/idris2
make test only=idris2/basic/basic001 INTERACTIVE='' < /dev/null
```

- `make idris2-exec` checks the changed modules of `src/` and those that
  import them (in parallel, `IDRIS2_JOBS`), then compiles the whole program
  to C and compiles that. Checking all of the compiler takes about 2.5
  minutes on 16 cores and compiling the executable about 90 s, so even a
  one-line change costs a couple of minutes. It writes
  `build/exec/idris2` (a launcher script) and `build/exec/idris2_app/idris2`
  (the binary).
- `make libs` rebuilds the libraries with the new compiler, but only the
  modules whose sources or imports changed, or whose TTC came from another
  compiler *commit*. Uncommitted compiler edits keep the same version, so
  when your change affects what goes into library TTCs (elaboration,
  inlining, specialisation, the TTC contents), run `make clean-libs && make
  libs` in your own tree. `make base`, `make contrib` and so on build one
  library and those it needs.
- `make` (= `make all`) does both. Use it when unsure.
- `make test` never rebuilds anything: it tests whatever `build/exec/idris2`
  and `libs/*/build` hold. Rebuild first.

Run the fresh compiler on a file of your own without installing it. Its
installation prefix is baked in at build time (`PREFIX`, `~/.idris2` by
default), so by itself it would load the *installed* libraries. Point it at
the test prefix, which links to the libraries of the tree:

```sh
make testenv                     # creates build/env (make test does it too)
IDRIS2_PREFIX=$PWD/build/env build/exec/idris2 --exec main Foo.idr
```

Never `make install` or `idris2 --install` from a work-in-progress compiler
unless the task says so: `~/.idris2` holds the boot compiler and libraries
that every other build uses.

## Running tests

```sh
make test only=idris2/error INTERACTIVE='' < /dev/null           # a category
make test only="refc chez/atomicIORef001" except=refc/doubles INTERACTIVE='' < /dev/null
make retest INTERACTIVE='' < /dev/null                            # the failures of the last run
make test INTERACTIVE='' threads=8 < /dev/null                    # everything, at the end
```

- `only` and `except` are lists of words, each matched as a *substring* of
  the test path (`idris2/basic/basic001`, `refc/doubles002`). `only=basic001`
  also runs `ttimp/basic001` and `vmcode/basic001`.
- Always pass `INTERACTIVE=''` and `< /dev/null`. The default is
  interactive: on a failure it shows a diff and asks whether to overwrite
  `expected`, which either hangs an agent or, answered by a stray `y`,
  accepts output you have not read.
- Every run rewrites `tests/failures` with the failures of *that* run, and
  `make retest` reads it. A scoped run after the full suite loses the list:
  copy it first if you need it.
- A pool whose tool is missing (Chez, Node, Racket, a C compiler, OpenSSL)
  is skipped with `✗ ... not found`, not failed. "N/N tests successful"
  counts only what ran; read the pool banners.
- On a shared machine pass `threads=N` (default: all processors) and
  `IDRIS2_JOBS=N`.

When a test fails, read `tests/<path>/output` against `tests/<path>/expected`
(`diff -u`). Accept a new `expected` only after reading every changed line
and knowing why it changed: a test that fails for an unrelated reason looks
the same in the summary. The rule from
`docs/source/implementation/error-messages.rst`: never copy outputs over
expected files in bulk.

```sh
diff -u tests/idris2/error/errmsg001/expected tests/idris2/error/errmsg001/output
cp tests/idris2/error/errmsg001/output tests/idris2/error/errmsg001/expected   # only after reading it
```

Adding a test: copy a template from `tests/templates/` into an existing
category under the next free number (`tests/idris2/reg/reg061`, say),
edit `run` and the `.idr` files, run it once with `make test only=...`, review `output`, and copy it
to `expected`. A directory with a `run` file inside a category that a pool
of `tests/Main.idr` lists is picked up on its own; only a new category needs
a new pool. Details, helpers and tool requirements: `references/tests.md`.

## Definition of done

A change is done when all of these hold:

1. **A test.** A bug fix comes with a golden test that fails before and
   passes after; a feature with tests of what it does and of the errors it
   gives. Library code is tested under `tests/base`, `tests/contrib`,
   `tests/http`, ... or through the library's own tests.
2. **The suite passes** with the compiler and libraries rebuilt from your
   tree (`make` then `make test INTERACTIVE='' < /dev/null`), or every
   failure is explained and known to be unrelated (compare with a run on
   the unchanged tree).
3. **`CHANGELOG_NEXT.md`** has an entry in the right section (`Compiler
   changes`, `Building/Packaging changes`, `Backend changes` with `RefC`,
   `Chez`, `JavaScript`, `Library changes` with `Base`, `Contrib`,
   `Network`, `HTTP`, `TLS`, `Documentation`). Entries are full sentences
   saying what changed for the user and, for a fix, what happened before
   ("It used to ...").
4. **Docs** under `docs/source` when behaviour, a flag, a pragma or a
   message that users read changes. The CI builds them with
   `cd docs && uv run --frozen make html` (warnings are errors).
5. **Lint**: `python3 lint/lint.py` (trailing whitespace and the final
   newline in tracked `.idr` files; a new file counts once it is `git
   add`ed). Keep `.md`, `.rst`, `.c` clean too: `git diff --check`.
6. **Warnings**: CI builds the compiler with `IDRIS2_BOOT="idris2 -Werror"`,
   so a new warning in `src/` fails it. Build with
   `IDRIS2_BOOT="$HOME/.idris2/bin/idris2 -Werror"` before you finish.
7. **Library API**: when a public definition of `prelude`, `base`,
   `contrib`, `http`, `tls` or `http-tls` changes, `make api-check` shows
   the difference; if it is intended, `make api-snapshots` and commit
   `libs/api` with the change (the test `idris2/mkdoc/apidump002-libs` checks
   the same).
8. **TTC version**: when what a TTC file stores changes (a `TTC` instance in
   `src/Core/TTC.idr` or `src/Core/Binary.idr`, a new field or flag of a
   definition that is serialised), bump `ttcVersion` in
   `src/Core/Binary.idr`. The rule written there: the current date as
   `YYYY_MM_DD_00`, or the next auxiliary number if it was already bumped
   that day. Say so in the changelog ("The TTC format version changes
   accordingly"). Two branches that both bump need one more bump when
   merged.
9. **Gaps you found but did not fix** go to `ROADMAP.md`, with what a fix
   would need.

## Error messages and codes

Read `docs/source/implementation/error-messages.rst` before changing any
message. The parts that matter most:

- Messages are built in `src/Idris/Error.idr` (`perrorRaw`, `pwarningRaw`)
  from `Error` and `Warning` in `src/Core/Core.idr`. Print terms with
  `pshow`, never `show`.
- Some phrases are an interface that `failing` blocks and tools match:
  `Mismatch between:`, `When unifying`, `Can't find an implementation for`,
  `Undefined name`, `is not covering`, `is not total`, `While processing`,
  and the others listed there. Do not reword or split them. Search first:
  `grep -rn 'failing "' tests libs docs`.
- Error codes (`E` or `W` and four digits, the first two the area) live in
  `src/Idris/ErrorCode.idr`. To add one: a case in `errorCode` (or
  `warningCode`) for the new constructor, an entry in `registry` with the
  next free code of its area (`stub` for a title only, `explained` with
  meaning, example and fixes), then write the reference page from the
  registry and check it:

```sh
build/exec/idris2 --list-error-codes > docs/source/reference/error-codes.rst
make test only=idris2/error/errorcodes001 INTERACTIVE='' < /dev/null
```

  A code is never renumbered or reused; an error that only adds context
  takes the code of the error inside it.

## Commits

Commit only when the task asks. One logical change per commit, with its
test, changelog entry and docs. Subject `[ area ] Sentence` in the
imperative, no final full stop; areas in use include `refc`, `doc`, `test`,
`perf`, `build`, `core`, `spec`, `contrib`, `chez`, `prelude`, `base`,
`elab`, `totality`, `compiler`, `node`, `js`, `new`. The body explains why,
what was measured and what was left out, wrapped at about 75 columns. See
`git log -40 --format='%B'` for examples. A change that touches many
`expected` files only for wording goes in a commit of its own.

Upstream's `CONTRIBUTING.md` ("Things We Will Not Accept") refuses
contributions that come from generative AI or coding agents. Work stays on
this fork: do not open pull requests or issues against upstream
`idris-lang/Idris2`, and do not push anywhere unless the owner says so.
