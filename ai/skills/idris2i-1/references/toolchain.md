# Driving the compiler from a shell

Everything here runs without a terminal session. `idris2i-1` stands for the compiler
found by `scripts/idr-find`; the scripts `idr-check` and `idr-q` call it for you.

Contents: [checking](#checking) · [asking questions](#asking-questions) ·
[working with holes](#working-with-holes) · [finding library functions](#finding-library-functions) ·
[building and running](#building-and-running) · [errors as JSON](#errors-as-json) ·
[options worth knowing](#options-worth-knowing) · [upstream differences](#upstream-differences)

## Checking

```sh
idris2i-1 --check File.idr                 # type-check one file and what it imports
idris2i-1 --find-ipkg --check src/A/B.idr  # same, inside a package (uses its .ipkg)
idris2i-1 --typecheck pkg.ipkg             # every module of a package
scripts/idr-check File.idr              # --find-ipkg --check, then lists the holes left
```

- Exit status is 0 on success and 1 on any error.
- Several independent errors are reported in one run; a parse error stops at the first.
- Errors go to standard output, progress lines (`1/3: Building ...`) too.
- A file with holes checks successfully. `idr-check`, or the REPL command `:m`, lists
  them. A signature without a definition also counts as a hole.
- Checking writes `build/ttc/` next to where you run it. Run from the package root, or
  pass `--build-dir DIR`, so that it does not appear in odd places.
- Outside a package, a module `A.B` must be checked from the directory that contains
  `A/`, or with `--source-dir`; otherwise: `Module name A.B does not match file name`.

## Asking questions

A REPL command can be run from the shell in two ways:

```sh
idris2i-1 File.idr --client ':t name'                 # one command (only the last --client counts)
printf ':t name\n:doc Vect\n:q\n' | idris2i-1 --no-banner File.idr   # several
scripts/idr-q File.idr ':t name' ':doc Vect'       # several, prompts removed
scripts/idr-q ':module Data.String' ':t parsePositive'   # no file: Prelude plus modules
```

Input piped to the REPL must end with a newline; end it with `:q`. Inside a package
add `--find-ipkg` (the scripts do).

| Command | Answer |
|---|---|
| `:t expr` | its type; for a hole, the variables in scope with their quantities, then the goal |
| `:ti expr` | the type with implicit arguments shown |
| `:doc name` | documentation, constructors or methods, totality, visibility; works on keywords too |
| `:printdef name` | the clauses of a definition in the loaded file |
| `:search type` | functions with that type, e.g. `:search List a -> Maybe a` |
| `:browse Module` | everything the module exports, with types (the module must be imported: `:module M` first, or import it in the file) |
| `:module M`, `:package p` | import a module, add a package, for the rest of the session |
| `:total name` | `name is total` or the reason it is not |
| `:missing name` | the clauses that are missing |
| `:m` | all holes with their types |
| `:explain E0101` | the long explanation of a code (this fork) |
| `expr` | evaluates it; `:exec expr` compiles and runs an `IO` action |

`:search` matches the type you write closely; if it prints nothing, generalise the
query or use `:browse`.

## Working with holes

Write `?name` where an expression is missing. The file checks, and `:t name` shows what
is available and what is needed:

```text
$ scripts/idr-q Holes.idr ':t append_rhs'
 0 m : Nat
 0 a : Type
 0 n : Nat
   ys : Vect m a
   xs : Vect n a
------------------------------
append_rhs : Vect (plus n m) a
```

The `0` in the first column marks an erased variable: it can appear in types but not
in the expression you write.

The compiler can write code. Line numbers count from 1; the name is the variable or
hole on that line.

| Command | What it produces |
|---|---|
| `:ac LINE fn` | a first clause for the signature on that line |
| `:cs LINE COL var` | the clause on that line split by the constructors of `var` (`COL` is a column inside the name) |
| `:gd LINE fn` | a whole definition for the signature on that line, when the types pin it down |
| `:ps LINE hole` | an expression for the hole, found by search; `No search results` is common |
| `:mc LINE hole`, `:mw LINE hole` | a `case` or `with` skeleton around the hole |
| `:ml LINE hole` | a helper function with the hole's context as arguments |
| `:typeat LINE COL name` | the type of a local name at that place |

```text
$ scripts/idr-q Holes.idr ':cs 8 8 xs' ':gd 10 zipV'
append [] ys = ?append_rhs_0
append (x :: xs) ys = ?append_rhs_1
zipV [] [] = []
zipV (x :: xs) (y :: ys) = (x, y) :: zipV xs ys
```

Without `!` a command prints the new lines for you to paste. With `!` (`:cs! 8 8 xs`)
it rewrites the file in place and leaves a backup `File.idr~`; delete the backup, and
re-read the file before editing it again. Check what `:gd` and `:ps` wrote: they find
*a* well-typed term, and for loosely typed functions (lists, numbers) that is often
not the one you meant.

A program with holes compiles, with a warning, and stops at run time with
`Encountered unimplemented hole`.

## Finding library functions

Installed libraries have no source files, so the compiler is the documentation:

```sh
scripts/idr-q ':module Data.SortedMap' ':browse Data.SortedMap'   # what a module offers
scripts/idr-q ':module Data.String' ':doc split'                   # one function
scripts/idr-q ':module Data.List' ':search (a -> Bool) -> List a -> List a'
idris2i-1 --list-packages                                              # installed packages
```

An `Undefined name` error usually ends with the import that provides the name
("Suggestion: Data.List exports sortBy; add import Data.List"). Modules of `base` need
only the import; other packages also need `-p pkg` or a `depends` line (see
`project.md`).

## Building and running

```sh
idris2i-1 Main.idr -o hello          # executable: build/exec/hello
./build/exec/hello arg1 arg2
idris2i-1 Main.idr --exec main       # compile and run once; exit status is the program's
idris2i-1 --build pkg.ipkg           # a package; its executable also lands in build/exec/
```

The default back end is RefC (this fork): Idris2i-1 → C → native code, and it needs a C
compiler (`cc`). `--cg chez`, `--cg node` and others select another back end when
its tools are installed. `getArgs` returns the program name first.

## Errors as JSON

`--error-format json` (this fork) prints one object per error or warning on standard
output; progress lines go to standard error.

```sh
idris2i-1 --check --error-format json File.idr 2>/dev/null
```

```text
{"severity":"error","file":"Foo.idr","start":{"line":10,"col":13},"end":{"line":10,"col":19},
 "message":"While processing right hand side of sorted. Undefined name sortBy.\nSuggestion: ...",
 "code":"E0201","headline":"Undefined name sortBy.",
 "context":["While processing right hand side of sorted"],
 "expected":..., "got":..., "candidates":[], "related":[],
 "suggestions":[{"module":"Data.List","import":"import Data.List"}], "notes":[...]}
```

Lines and columns count from 1. Use it when a program has to read the errors; for
reading them yourself the default format, which shows the source lines, is better.

## Options worth knowing

| Option | Effect |
|---|---|
| `--find-ipkg` | use the `.ipkg` found in a parent directory |
| `-p pkg` | add a package; repeat for every package, dependencies included |
| `--source-dir DIR`, `--build-dir DIR`, `--output-dir DIR` | override directories |
| `--total` | as if every file started with `%default total` |
| `-Werror` | warnings fail the build |
| `--no-color`, `--console-width 0` | plain output on one line each; good for logs |
| `--explain CODE`, `--list-error-codes` | the reference for error codes (this fork) |
| `--cg NAME` | back end: `refc` (default), `chez`, `node`, `javascript` |
| `--timing-summary` | where compile time went (this fork) |
| `--log topic:N` | compiler logging; `--help logging` lists topics |
| `--show-implicits` | print implicit arguments in types and errors |

`idris2i-1 --help` lists everything, including environment variables (`IDRIS2I_1_CG`,
`IDRIS2I_1_PREFIX`, `IDRIS2I_1_PACKAGE_PATH`, `IDRIS2I_1_CC`, `IDRIS2I_1_CFLAGS`).

## Upstream differences

`idris2i-1 --version` prints `0.1.0-<hash>` here. If `idris2i-1 --explain E0101` is rejected
as an unknown option, the compiler is upstream Idris 2: errors carry no codes, there is
no JSON format and no import suggestion, the default back end is Chez Scheme, and
`div`/`mod` do not affect totality. The language rules in this skill still hold.
