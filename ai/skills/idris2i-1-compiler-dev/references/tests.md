# The golden tests

All of this is in the compiler repository. The runner is
`tests/Main.idr`, built on the `test` library (`libs/test/Test/Golden.idr`);
`tests/README.md` and `tests/templates/*/notes.md` are the upstream notes
(some of their advice is out of date, as said below).

## Contents

- Layout
- Pools and requirements
- Running
- What a test sees: `testutils.sh`
- How `expected` is compared and regenerated
- Adding a test
- Tools that groups need

## Layout

```text
tests/<group>/<category>/<name>/
    run         shell script, run as `sh ./run "<idris2i-1> [--cg CG]"`
    expected    the stdout the run must print, byte for byte
    input       optional: REPL input, fed with `< input` by run
    *.idr, *.ipkg, ...
    output      written by the runner (gitignored)
```

Most groups have categories (`tests/idris2i-1/basic/basic001`,
`tests/idris2i-1/error/errmsg001`); others are one level (`tests/refc/doubles`,
`tests/chez/atomicIORef001`, `tests/ttimp/basic001`). Names are a
descriptive word and a 3-digit number. The test name the runner prints and
matches is the path below `tests/`.

## Pools and requirements

`tests/Main.idr` lists pools, each made with `testsInDir "<dir>" "<title>"`.
`testsInDir` takes every subdirectory of `<dir>` that contains a `run`
file, so a new test inside an existing directory needs no change to
`Main.idr` (the template notes saying "update `tests/Main.idr`" predate
this). A new category, a new directory under `tests/`, or a test that needs
a back end or tool does need a pool or an entry.

A pool can say:

- `codegen = Just Chez` (or `C`, `Node`): the runner passes
  `--cg <name>` inside `$1`, and the pool is skipped if that tool is missing.
  Without it, no `--cg` is passed and the compiler uses its default (RefC).
- `requirements = [...]`: tools that must exist, without changing the
  back end (`base`, `contrib` and `linear` need both Chez and Node).
- `pred`: tests of the directory to leave out (`chez/channels009`, some
  `allbackends` tests on some back ends).

`allschemes` runs once per Scheme back end and `allbackends` once for each
of Chez, Node and C. `idris2i-1/schemeeval` runs only when the
compiler under test runs on Scheme (it is skipped for a RefC-built
compiler). `tls` and `http-tls` run only when the libraries were built
(OpenSSL 3, `IDRIS2I_1_TLS`) and the `openssl` tool is on `PATH`.

A pool whose requirement fails prints `✗ <tool> not found` in its banner
and is skipped. The final `N/N tests successful` does not count it.

## Running

Through the top-level `Makefile` only: it builds the test environment
(`make testenv`: support libraries in `build/env`, links to the libraries,
the runner `tests/build/exec/runtests`) and exports `NAME_VERSION`, which
`clean_version` in `testutils.sh` needs. Running `tests/build/exec/runtests`
or `make -C tests` by hand without it makes version strings and module
lookups fail.

```sh
make test only=idris2i-1/basic/basic001 INTERACTIVE='' < /dev/null
make test only="idris2i-1/error idris2i-1/warning" INTERACTIVE='' < /dev/null
make test only=refc except=refc/doubles INTERACTIVE='' < /dev/null
make retest INTERACTIVE='' < /dev/null
make test INTERACTIVE='' threads=8 < /dev/null
```

- `only` and `except` are split into words; a test runs when its path
  contains one of the `only` words as a substring and none of the `except`
  words. `only=idris2i-1/basic001` matches nothing (the path is
  `idris2i-1/basic/basic001`), although `tests/README.md` gives it as an
  example.
- `make retest` runs the tests listed in `tests/failures`. Every run of
  `make test` overwrites that file with its own failures, an empty list
  included.
- `threads` defaults to the number of processors; `--timing` is always on,
  so each line shows how long the test took.
- `INTERACTIVE` defaults to `--interactive`: on a failure the runner shows
  `git diff --no-index --word-diff-regex=. expected output` and asks
  `Accept actual value as new golden value? [y/N]`, and on a missing
  `expected` offers to write it. An agent must pass `INTERACTIVE=''` and
  `< /dev/null`; non-interactive failures print `Expected:` and `Given:`
  instead.
- The whole suite has about 1300 tests, many of which compile programs with
  a C compiler; its running time is not documented. Run scoped tests while
  working and the full suite once before you finish.

## What a test sees: `testutils.sh`

A `run` script starts with `. ../../../testutils.sh` (as many `../` as it
is deep). Sourcing it removes `build/` and `prefix/` in the test
directory, sets `LC_ALL=C.UTF-8`, points `IDRIS2I_1_PREFIX` at a fresh
`prefix/` inside the test (with the test prefix `build/env` still on the
package path, so `--install` in a test stays inside it), and defines:

| Helper | Does |
|---|---|
| `idris2i-1 ARGS` | `$1 --no-banner --console-width 0 --no-color ARGS`, piped through `clean_names` |
| `idris2i_1_no_clean ARGS` | the same without `clean_names` |
| `check FILE` | `idris2i-1 --check FILE` |
| `run FILE` | `idris2i-1 --exec main FILE` |
| `clean_names` | numbers machine names, `ttc/<version>`, `$resolvedN`, `PE_..._hash` and source locations of case/with blocks consistently, so that `expected` does not depend on them |
| `clean_version` | replaces the compiler version (`$NAME_VERSION`) by `idris2i-1-x.y.z` |
| `filter_test_dir` | replaces the test's absolute directory by `__TEST_DIR__` |
| `safesort` | `sort` in the C locale |
| `sed_literal`, `windows_path_tweaks` | path helpers |
| `append_package_path DIR` | adds to `IDRIS2I_1_PACKAGE_PATH` |
| `$VALGRIND prog` | runs under Valgrind (`tests/valgrind.sh`) when it is installed |
| `TIMEOUT=N` | set before `idris2i-1` calls to kill the compiler after N seconds |

`${IDRIS2I_1_TESTS_CG}` names a back end for scripts that pick one
themselves.

## How `expected` is compared and regenerated

The runner runs `sh ./run "<exe>" | tr -d '\r' > output` and compares
`output` with `expected` as whole strings. Only **stdout** is captured:
anything a test must check on stderr needs `2>&1` in `run`. The exit code
of `run` is ignored, so print it (`echo $?`) when it matters.

To regenerate an `expected` file on purpose:

```sh
make test only=idris2i-1/error/errmsg001 INTERACTIVE='' < /dev/null
diff -u tests/idris2i-1/error/errmsg001/expected tests/idris2i-1/error/errmsg001/output
cp tests/idris2i-1/error/errmsg001/output tests/idris2i-1/error/errmsg001/expected
```

Read the whole diff first. Each changed line must be one you can explain
by your change; otherwise the test found something. After a change to an
error message, also look at `tests/idris2i-1/error/jsonerror001` and the IDE
mode tests (`tests/ideMode`), which carry the same text in another form;
`tests/ttimp` print errors raw and seldom change. A diff that only moves a
machine-generated number usually means a `run` script lacks
`clean_names`, not that `expected` should change.

## Adding a test

1. Pick the directory: a regression under `tests/idris2i-1/reg`, an error
   message under `tests/idris2i-1/error`, a back end under `tests/refc` or
   `tests/chez`, a library under `tests/base`, `tests/contrib`,
   `tests/http`... Take the next free number.
2. Copy a template from `tests/templates/`: `simple-test` (one module and a
   REPL `input`), `with-ipkg` (a package), `ttimp` (a `.yaff` file for
   `--yaffle`). Copy only `run`, `input`, the sources and `expected`, not
   the `build/` or `output` that a previous run left there, and fix the
   number of `../` in the `. ../../testutils.sh` line for the new depth.
3. Write `run` so that it cleans up what it creates besides `build/`
   (deleted by `testutils.sh`), ends REPL input with `:q`, and does not
   write files named `run`, `expected` or `output`.
4. Run it, read `output`, copy it to `expected`. A test for a bug fix
   should fail on the compiler without the fix: run it once against the
   unchanged compiler (or say why that was not possible).
5. Lint applies to the `.idr` files of the test.

## Tools that groups need

| Group | Needs |
|---|---|
| most of `idris2i-1/*`, `ttimp`, `typedd-book`, `ideMode`, `prelude`, `codegen`, `cli`, `http`, `vmcode`, `templates` | only the compiler; those that run programs use RefC, so a C compiler and GMP |
| `refc`, `allbackends` (C instance) | C compiler (`CC` or `cc`) |
| `chez`, `chezsep`, `allschemes`, `allbackends` (Chez) | Chez Scheme (`CHEZ`, or `chez`, `chezscheme`, `scheme`...) |
| `node`, `allbackends` (Node) | Node.js |
| `base`, `contrib`, `linear` | Chez and Node both |
| `tls`, `http-tls` | the libraries built (OpenSSL 3) and `openssl` |
| `idris2i-1/schemeeval` | a compiler built with Chez |
