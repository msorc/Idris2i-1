# Slow type checking and slow builds

Read this when `idris2i-1 --check`, `--build` or `--typecheck` takes seconds or minutes on
a module that is not huge. Ratios marked *measured* were measured for this skill
(processor time and `perf stat` instructions of `idris2i-1 --check` on generated files, 3
runs each, with a fresh `--build-dir` so nothing was reused). An empty module checks in
about 0.05 s, so anything over a second is worth finding.

<!-- idris
import Data.IORef
-->

## Find the definition first

`--timing-summary` names the module and its ten most expensive declarations, with the
phase the time went to (microseconds of processor time):

```sh
rm -rf build && idris2i-1 --timing-summary --check Main.idr 2>&1 | grep 'PROFILE \(module\|decl\)'
idris2i-1 --timing-summary --build my.ipkg            # every module of a package
```

```text
PROFILE module P100.idr cpu=6237162 search=4354297 solve=1411392 decl=220214 compile=144832 ...
    #search.run=187537 #search.rejected.hint=4341 #solve.scans=663 ...
PROFILE decl P100.idr "P100:3:1--105:26" cpu=6014453 search=4354297 solve=1411328 ...
```

Read the self times: `search` is auto-implicit and interface resolution, `solve` is
constraint solving, `ambig` is resolving overloaded names, `casetree`/`coverage`/
`totality` are the checks of pattern matches, `compile` is inlining and compilation
to the intermediate forms, `import`/`decode` is loading other modules. The counters
say how often: above, 100 `do` statements ran 187,537 searches. A declaration is
named by its source span (`"P100:3:1--105:26"` is the clause of `main` on lines 3 to
105).

Remove the build directory (or touch the file) before measuring: a module whose TTC
is up to date is not checked again, and its warnings are not printed again either.

`--timing N` prints a tree of phases (`TIMING + Elaborating Main.idr: 11.480s`, more
lines with a higher `N`). It does not include the C compiler: when building an
executable is slow and `Code generation overall` is small, the time is in `cc` (see
the end of this file).

## Long `do` blocks

The ROADMAP of the compiler: "A long `do` block is checked in time that grows faster
than its length (200 statements take about 1.9 s), mostly in nested delayed case
blocks; untyped numeric literals make it much worse." *Measured*, `main = do` followed
by N statements:

| Statements | Statement | Time | vs. |
|---|---|---|---|
| 100 | `modifyIORef r (+ 7)` | 2.6 s | |
| 200 | `modifyIORef r (+ 7)` | 12 s | 4.3× the 100-statement block |
| 200, in 4 functions of 50 | `modifyIORef r (+ 7)` | 2.6 s | 4.5× faster than one block |
| 200 | `printLn (7 + 1)` | 21 s | |
| 200 | `printLn (the Int (7 + 1))` | 11 s | 2× faster than untyped |

Mechanism: every statement is checked under the binds before it, and a literal whose
type is not yet known (`7` in `printLn (7 + 1)` needs `Num a` and `Show a` for an
unknown `a`) is a search that is postponed and retried; the counters above show
thousands of searches per statement. Doubling the block roughly quadruples the time.

What to do, in order of effect:

1. **Split the block** into functions of a few dozen statements, each with a type
   signature. Checking cost is per block, so this is the reliable fix.
2. **Give literals and intermediate values a type**: `the Int 7`, a `let` with a type,
   or a helper with a signature. (`(7 : Int)` is a parse error, E1101.)
3. Statements whose types are already fixed (`modifyIORef r (+ 7)` with `r : IORef Int`)
   gain nothing from annotations: there, only splitting helps (the measured
   `the Int` version of that statement took the same time).

```idris
step1 : IORef Int -> IO ()
step1 r = do
  modifyIORef r (+ 1)
  modifyIORef r (+ 2)

step2 : IORef Int -> IO ()
step2 r = do
  let k : Int
      k = 10
  modifyIORef r (+ k)
  printLn (the Int 3 + 4)

runAll : IO ()
runAll = do
  r <- newIORef (the Int 0)
  step1 r
  step2 r
  readIORef r >>= printLn
```

## Computation in types

At type-checking time `Nat` is unary: `S (S (S Z))`. (At run time it is an `Integer`,
see `runtime.md`; the two are different things.) *Measured*: checking
`x : the Nat (200 * 200) = 40000; x = Refl` took 1.2 s, the same with `Integer`
0.05 s (no more than an empty module). Arithmetic on large `Nat`s in types, `Vect`
lengths of thousands, and proofs by `Refl` of big computations all pay for it. The
ROADMAP: "Type-level evaluation of a long computation is slow and deep" (one test of
the compiler takes 135 G instructions and 1.6 GB).

What to do: keep type-level numbers small; prove facts about `n` rather than
computing with concrete large values; move a big computed constant out of the type
(check it at run time, or prove it by a lemma instead of `Refl`).

## Interface and `auto` search

Each use of an overloaded method or an `auto` implicit is a search over the
implementations and hints in scope, depth-bounded by `%auto_implicit_depth` (default
50). It is cheap when the types are known and expensive when they are not: an
unknown type makes the search wait and be retried (the `do` block case above), and
an implementation that needs others (`Show (List (Maybe a))`) searches for each. In
`--timing-summary`, a large `search` time with a large `#search.run` points here.
Fix by giving the types that pin the implementation, at the declaration that
`--timing-summary` names.

## Ambiguous names

A name defined in several namespaces (`++` on lists and strings, list literals with
`Data.Vect` imported) is elaborated once per alternative, nested up to
`%ambiguity_depth` (default 3; the pragma reference warns that raising it costs
compile time). *Measured*: a chain of 80 `++` with string literals and `show` checked
in 0.12 s, as fast as `fastConcat [...]`, because the expected type `String` decides
each alternative at once. Ambiguity is slow when nothing fixes the type; the
counters `#ambig.sites` and `#ambig.alts` show it. Fix with a signature, `the`, or a
qualified name.

## Package builds

- `--jobs N` (`-j N`, or `IDRIS2I_1_BUILD_JOBS`) checks the modules of a package in up to
  `N` processes, each module once its imports are done (this fork; for the
  modules of a package, `--build` or `--typecheck` of an `.ipkg`). The CHANGELOG: `base` builds in 20 s instead of 70 s on
  16 cores. It cannot split one module: a big module that everything imports
  serialises the build, so split it.
- `--typecheck pkg.ipkg` skips code generation.
- A module is rebuilt only when its source or the interface of an import changed; a
  rebuild with nothing to do takes a fraction of a second. **A TTC written by another
  compiler version is rebuilt**, so the first build after changing compilers checks
  everything.
- `IDRIS2I_1_TTC_CACHE_MB` (default 32) is how much of the imported TTC files one process
  keeps between modules.

## Slow C compilation (RefC)

Building an executable runs the C compiler after the Idris2i-1 compiler, and that time is
not in `--timing`. From the RefC documentation: a program over 4 MB of C is compiled
in units by parallel C compilers (`IDRIS2I_1_CC_JOBS`), and a unit whose text did not
change is not compiled again; `-DIDRIS2I_1_REFC_SMALL_CODE` in `IDRIS2I_1_CFLAGS` gives
about 10% less code, compiled about as much faster; `--directive refc-size-reuse`
is off by default because it makes GCC very slow on some big functions; to use
`ccache`, point `IDRIS2I_1_CC` at a script that runs `ccache gcc` (it takes a program
name, not a command line).
