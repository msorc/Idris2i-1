# Packages, builds and tests

The commands and files below were run as written; `idris2i-1` is the compiler found by
`scripts/idr-find`.

Contents: [one file](#one-file) · [a package](#a-package) · [`.ipkg` fields](#ipkg-fields) ·
[dependencies](#dependencies) · [commands](#commands) · [tests](#tests) ·
[back ends](#back-ends)

## One file

A program in a single file needs no package:

```sh
idris2i-1 Main.idr -o hello && ./build/exec/hello
idris2i-1 -p contrib Main.idr -o hello      # when it imports from another package
```

Move to a package as soon as there are several modules or a dependency: the package
file records the source directory and the dependencies once, for every command.

## A package

```text
wc/
  wc.ipkg
  src/
    Main.idr            module Main
    Text/Count.idr      module Text.Count
  tests/
```

```text
package wc
version = 0.1.0
authors = "A. Author"

sourcedir = "src"
depends = base, contrib
modules = Text.Count
main = Main
executable = wc
```

The module name fixes the file path: `Text.Count` is `src/Text/Count.idr`. When they
disagree the error is `Module name Text.Count does not match file name`.

`src/Text/Count.idr` starts with its header and imports:

```text
module Text.Count

import Data.String
```

<!-- idris
import Data.String
-->

```idris
%default total

||| Lines, words and characters of a text.
public export
record Counts where
  constructor MkCounts
  lines, words, chars : Nat

export
count : String -> Counts
count s = MkCounts (length (lines s)) (length (words s)) (length s)

export
Show Counts where
  show c = "\{show c.lines} \{show c.words} \{show c.chars}"
```

`src/Main.idr` (shown as text because this file is checked as one module):

```text
module Main

import System
import System.File
import Text.Count

main : IO ()
main = do
  [_, path] <- getArgs                      -- the first element is the program name
    | _ => die "usage: wc FILE"
  Right text <- readFile path
    | Left err => die "wc: \{path}: \{show err}"
  printLn (count text)
```

```text
$ idris2i-1 --build wc.ipkg
1/2: Building Text.Count (src/Text/Count.idr)
2/2: Building Main (src/Main.idr)
Now compiling the executable: wc
$ ./build/exec/wc notes.txt
2 3 6
$ ./build/exec/wc; echo $?
usage: wc FILE
1
```

Things this small program shows:

- `die` prints to standard error and exits with status 1; `exitWith (ExitFailure n)`
  and `exitSuccess` are the general forms (`import System`).
- `readFile` returns `Either FileError String`.
- `readFile` and other functions that loop on input are `covering`, not `total`. If
  `Main` had `%default total` (or the package had `opts = "--total"`), `main` would be
  rejected with E0703, "possibly not terminating due to function Data.Fuel.forever
  being reachable". Keep `%default total` in library modules and declare `main` and
  IO loops `covering`.

## `.ipkg` fields

| Field | Meaning |
|---|---|
| `package NAME` | first line, required |
| `version = 0.1.0` | no quotes |
| `authors`, `license`, `brief`, `homepage`, `sourceloc`, `readme` | strings, optional |
| `sourcedir = "src"` | where modules live; default is the directory of the `.ipkg` |
| `depends = base, contrib, foo >= 0.2 && < 1.0` | packages, with optional version bounds |
| `modules = A, A.B` | library modules to build and install (not needed for `Main` and what it imports) |
| `main = Main` | the module with `main`, for an executable |
| `executable = name` | file name of the executable in `build/exec/` |
| `opts = "--total -Werror"` | compiler options for every module |
| `builddir`, `outputdir` | default `build` and `build/exec` |
| `prebuild`, `postbuild`, `preinstall`, `postinstall`, `preclean`, `postclean` | shell commands |

An unknown field is an error (`Unrecognised property`). Comments start with `--`.

## Dependencies

- In an `.ipkg`, `depends` is followed through: `depends = http` also brings in what
  `http` depends on.
- On the command line, `-p` is not: `idris2i-1 -p http File.idr` fails with
  `Module Network.Socket.Async not found` until `-p network -p contrib` are added too.
  This is the main reason to prefer a package file with `--find-ipkg`.
- `prelude` and `base` are always available. `idris2i-1 --list-packages` shows what is
  installed; the usual set is `contrib`, `linear`, `network`, `test`, and in this fork
  `http`, `tls`, `http-tls`.
- A module that is not found (E1201) means a missing `depends`/`-p`, or a module that
  does not exist here. `scripts/idr-q ':package contrib' ':module Data.HashMap'
  ':browse Data.HashMap'` answers which.
- There is no package manager in the compiler. If `pack` is installed the project may
  use `pack.toml`; do not assume it is.

## Commands

| Command | Does |
|---|---|
| `idris2i-1 --build [pkg.ipkg]` | compile modules and the executable; with no argument, the `.ipkg` in the current directory |
| `idris2i-1 --typecheck pkg.ipkg` | check all modules without generating code |
| `idris2i-1 --find-ipkg --check src/A/B.idr` | check one module with the package's settings, from any directory inside it |
| `idris2i-1 --find-ipkg src/Main.idr --client ':t f'` | REPL command inside the package |
| `idris2i-1 --clean pkg.ipkg` | remove build products |
| `idris2i-1 --install pkg.ipkg` | install the library where other packages can `depends` on it (`--dump-installdir` shows where) |
| `idris2i-1 --mkdoc pkg.ipkg` | HTML documentation from `\|\|\|` comments, in `build/docs` |
| `idris2i-1 --build pkg.ipkg -j 8` | build modules in parallel (this fork) |

`--init` asks questions on the terminal; write the `.ipkg` by hand instead.

## Tests

The `test` package provides golden tests: a test is a directory with a `run` script and
an `expected` file, and it passes when the script's standard output equals `expected`.

```text
tests/
  tests.ipkg
  Tests.idr
  cases/
    basic/
      run
      expected
```

`tests/tests.ipkg`:

```text
package tests
depends = test
main = Tests
executable = runtests
```

`tests/Tests.idr`:

```text
module Tests

import Test.Golden

main : IO ()
main = runner [ !(testsInDir "cases" "wc") ]
```

`tests/cases/basic/run` (run by `sh` in its own directory; `$1` is the first argument
given to the runner):

```sh
printf 'a b\nc\n' > in.txt
$1 in.txt
rm in.txt
```

```text
$ cd tests && idris2i-1 --build tests.ipkg
$ ./build/exec/runtests "$PWD/../build/exec/wc"
cases/basic: success
1/1 tests successful
```

- The runner exits with 1 when a test fails and prints `Expected:` and `Given:`.
- It writes the actual output to `cases/basic/output`; add that name to `.gitignore`.
- `--only NAME` runs the tests whose path contains `NAME`; `--interactive` offers to
  accept new output as `expected`; `--threads N` runs in parallel.
- Pass the program under test as an absolute path: each `run` executes in its own
  directory.
- To test library functions, have `run` execute a small Idris2i-1 program that prints
  results: `idris2i-1 --find-ipkg Check.idr --exec main`.

For properties that must hold for all inputs, state them as types and let the checker
prove them (the `idris2i-1-proofs` skill); a `failing` block asserts that code is rejected:

```idris
failing "Can't find an implementation for FromString Nat"
  wrong : Counts
  wrong = MkCounts 1 2 "three"
```

## Back ends

| `--cg` | Needs | Notes |
|---|---|---|
| `refc` (default, this fork) | a C compiler | native executable; reference counting |
| `chez` | Chez Scheme | upstream's default |
| `node`, `javascript` | Node.js, or a browser | `Int` is 32-bit; the output is a `.js` file |

`IDRIS2I_1_CG=chez` sets the default for a shell. Libraries with C parts (`network`,
`http`, `tls`) are meant for RefC and Chez; `http` does not work on JavaScript.
