---
name: idris2-performance
description: "Use when an Idris 2 program is slow, uses too much memory, or type-checks/compiles slowly: profiling RefC executables, Int vs Integer vs Nat, strings, arrays, `%inline`/`%spec`, tail calls, W0007, IORef cost, long do-blocks, `--timing-summary`. Also use before optimising hot loops. Covers perf, IDRIS2_REFC_MEMSTATS/LEAKCHECK, strIndex and ++ in loops, fastConcat, IOArray vs flat arrays vs Buffer vs Data.Array, List/Vect indexing, `--spec-interfaces`, stack overflow, Lazy not memoised, fork doing work in the parent, `--jobs`, slow C builds; use it instead of GHC habits (laziness, strictness, fusion, -O2)."
---

# Making Idris 2 programs and builds fast

The default back end of this compiler is RefC: Idris is compiled to C, the C to a
native executable with `cc -O2`. Evaluation is strict, memory is reference counted and
freed at once, there is no tracing GC. GHC folklore mostly does not apply:

- No thunks build up: `foldl` with an accumulator is fine, there is nothing to `seq`
  and no strictness annotation to add.
- `Lazy` is call-by-name: a lazy value forced twice is computed twice.
- No fusion: `map f (map g xs)` makes two passes and a middle list (`--dumpcases`
  shows two `mapAppend` calls); its cells are freed, or reused, as soon as it is dead.
- No `-O2` to add: the C compiler always gets `-O2`, there is no Idris `-O` flag, and
  `--profile` does nothing for RefC.
- `Nat` is an `Integer` at run time (and the `Data.Nat`/`Data.Fin` library functions
  work on `Integer`): not a unary list, but not a machine word either
  (4× the cost of `Int` for small values, GMP and an allocation per result past 32 bits).

So the costs are allocation, reference-count updates, closure calls, `Integer`
arithmetic, and a few compile-time traps. Measure before changing code: the commands
below are the ones that work with this compiler.

## 1. Where compile time goes

`--timing-summary` names the module, its ten most expensive declarations, and the
phase (microseconds of processor time). Remove the build directory first: an
up-to-date module is not checked again.

```sh
rm -rf build && idris2 --timing-summary --check Main.idr 2>&1 | grep 'PROFILE \(module\|decl\)'
idris2 --timing-summary --build my.ipkg 2>&1 | grep 'PROFILE \(module\|decl\)'
```

```text
PROFILE module P100.idr cpu=6237162 search=4354297 solve=1411392 decl=220214 compile=144832 ...
    #search.run=187537 #search.rejected.hint=4341 #solve.scans=663 ...
PROFILE decl P100.idr "P100:3:1--105:26" cpu=6014453 search=4354297 solve=1411328 ...
PROFILE process cpu=6257555 timed=6237162 untimed=20393 peak_rss_kib=55080
PROFILE timer search calls=187537 incl=4360875 self=4354297
```

Here one declaration (lines 3 to 105, a 100-statement `do` block) took 6 s, 70% of
it in interface search. `--timing 1` (or 2, 3 for more detail) prints a tree of
phases instead:

```text
TIMING + Elaborating PT200.idr: 11.480s
TIMING + Build deps: 11.524s
TIMING + Loading main file: 11.526s
...
TIMING + Code generation overall: 0.017s
```

The C compiler is not in `--timing`: when building an executable takes much longer
than the `TIMING` lines add up to, the time is in `cc`. Package builds check modules
in parallel with `--jobs N` (or `IDRIS2_BUILD_JOBS`; this fork). Then read
`references/typecheck-speed.md`.

## 2. Where run time goes (RefC executables)

Count instructions rather than seconds when the machine is busy: the count does not
change with load, wall time can swing by 50% or more.

```sh
idris2 -o prog Main.idr
perf stat -e instructions:u,task-clock ./build/exec/prog     # cost of one run
/usr/bin/time -f '%U s user, %e s wall, %M KB peak' ./build/exec/prog
```

Profile with the Idris names of functions (`refc-backtrace` adds a table of names, and
compiles every function `noinline` so each has a frame; `IDRIS2_REFC_DEMANGLE=1`
makes the program translate C names on its standard input instead of running):

```sh
IDRIS2_CFLAGS=-g idris2 --directive refc-backtrace -o prog Main.idr
perf record -g ./build/exec/prog
perf report --stdio --no-children | IDRIS2_REFC_DEMANGLE=1 ./build/exec/prog | less
```

```text
    54.78%  spec     spec                  [.] Main.insert
            |--29.46%--idris2_newReference (inlined)
            |--11.66%--idris2_newValue (inlined)
    14.93%  spec     spec                  [.] idris2_releaseValue
```

`idris2_newValue`, `idris2_releaseValue`, `idris2_freeValue` mean allocation;
`idris2_newReference`/`removeReference` reference counting; `idris2_apply_closure`
closure calls (interface methods, higher-order functions); `__gmpz_*` `Integer`
arithmetic; `idris2_slotGet` array reads through values. Other names: `Main_f` is
`Main.f`, `Main_f_0` a lambda or `where` block of it, `case__...` a case block.

`IDRIS2_CFLAGS` is added *after* `-O2`, so `-g` keeps the optimisation and an `-O`
of yours replaces it (`-O0` measured 2.5× the instructions; `-O3` 2% fewer).

Memory, reported on standard error when the program exits:

```sh
IDRIS2_REFC_MEMSTATS=1 ./build/exec/prog     # allocator pages and live values by size
IDRIS2_REFC_LEAKCHECK=1 ./build/exec/prog    # values never freed: reference cycles
IDRIS2_REFC_LEAKCHECK=2 ./build/exec/prog    # ... and some of them
```

```text
RefC leak check: 3000 leaked values, 0 constants and 0 values that they hold; 0 large values (from malloc, not looked at)
  leaked values: constructor 2000 IORef 1000
```

There is no cycle collector: a leak here is a cycle through an `IORef`, an array or a
stored closure, and stays until exit. For counts of allocations by kind and of
reference-count operations, build with `IDRIS2_CPPFLAGS=-DIDRIS2_REFC_STATS` (the
runtime library must be built with it too; see the RefC documentation). A crash or
stack overflow prints its frames with `IDRIS2_REFC_BACKTRACE=1`.

## 3. What the compiler produced

```sh
idris2 --dumpcases out.cases -o prog Main.idr    # case trees after inlining: erasure, Nat->Integer, inlining
idris2 --dumplifted out.lifted -o prog Main.idr  # after lambda lifting: where-blocks become functions
idris2 --dumpanf out.anf -o prog Main.idr        # A-normal form, closest to the C
less build/exec/prog.c                           # the generated C (in the build directory)
```

A `where` constant that is recomputed is visible in `--dumplifted` as a call with the
enclosing arguments inside the loop:

```text
Main.3443:2526:big = [{arg:0}][]: %op /Int(Prelude.Types.foldl({csegen:0}(), 0, !{arg:0}), 2)
Main.3443:2527:go = ... %op >Int(%op *Int(!{e:2}, 1000), Main.3443:2526:big(!{arg:0})) ...
```

In the C, a function `idris2_raw_Main_f` taking `int64_t`/`double` is the unboxed
worker of `Main.f`: its numbers are not allocated.

## 4. Symptom, likely cause, fix

| Symptom | Likely cause | Fix (details in) |
|---|---|---|
| numeric loop 4× to 50× slower than with `Int` | `Integer` or `Nat` counter/accumulator (GMP past 32 bits) | `Int`/`Bits64`; `cast` at the edges ([runtime](references/runtime.md#numbers)) |
| time grows with the square of the input in a string loop | `strIndex`/`substr`/`length` on non-ASCII text, or `acc ++ s` | `unpack` once, or collect pieces and `fastConcat` ([runtime](references/runtime.md#strings)) |
| quadratic, no strings involved; profile shows a `where` helper called from a loop | `where` constant recomputed at each use (W0007) | `let` it once and pass it; check with `-Wwhere-recompute` ([runtime](references/runtime.md#where-constants-are-recomputed-w0007)) |
| `idris2_apply_closure` high in generic code | interface dictionary calls | `%spec` on a named `auto` argument, or `--spec-interfaces` ([runtime](references/runtime.md#inline-noinline-spec-and---spec-interfaces)) |
| a tree/list function allocates on every step that only looks | as-pattern `t@(Node ...)` rebuilds the cell | match with `case t of` and return `t` ([runtime](references/runtime.md#records-and-constructors)) |
| an `IO` loop is slow, profile in `IORef` calls | state kept in an `IORef` | state in loop arguments, write the ref once ([runtime](references/runtime.md#ioref-and-io-loops)) |
| something lazy is computed twice | `Lazy` is not memoised | force once, bind the result ([runtime](references/runtime.md#the-model-to-hold)) |
| indexing a `List`/`Vect` in a loop is quadratic | `getAt`/`index` walk from the head | `Data.Array` (`index` in constant time) ([runtime](references/runtime.md#lists-arrays-and-buffers)) |
| memory high for numeric data | `List`/`IOArray` of boxed numbers | `Buffer`, or flat arrays ([runtime](references/runtime.md#lists-arrays-and-buffers)) |
| memory grows forever in a long-running program | reference cycle (no cycle collector) | `IDRIS2_REFC_LEAKCHECK=1`; break the cycle ([runtime](references/runtime.md#the-model-to-hold)) |
| exit status 139, no message | stack overflow, often in a forked thread (8 MB stack) | `IDRIS2_REFC_BACKTRACE=1`; tail recursion, or `IDRIS2_THREAD_STACK_SIZE` ([runtime](references/runtime.md#recursion-and-the-stack)) |
| parallel program not faster than one thread | work done in the parent: a `let` before the first action of the forked function | `v <- pure (work x)` or `pure ()` first ([runtime](references/runtime.md#concurrency-fork)) |
| one `do` block takes seconds to check | long block, untyped literals | split into typed functions; `the Int` ([typecheck](references/typecheck-speed.md#long-do-blocks)) |
| a proof by `Refl` or a `Vect` type takes seconds | unary `Nat` computed in a type | keep type-level numbers small ([typecheck](references/typecheck-speed.md#computation-in-types)) |
| large `search` in `--timing-summary` | interface/auto search on unknown types | add the types it waits for ([typecheck](references/typecheck-speed.md#interface-and-auto-search)) |
| package build slow, many modules | serial build | `--jobs N` ([typecheck](references/typecheck-speed.md#package-builds)) |
| building the executable slow after checking is fast | the C compiler | `-DIDRIS2_REFC_SMALL_CODE`, `IDRIS2_CC` with ccache ([typecheck](references/typecheck-speed.md#slow-c-compilation-refc)) |

## Reference files

- `references/runtime.md`: read before changing a hot loop or a data representation.
  The execution model, and the cost of numbers, strings, collections, records,
  recursion, `where` constants, inlining and specialisation, `IORef`, `fork`, and the
  C compiler knobs, each with its mechanism and a measured ratio.
- `references/typecheck-speed.md`: read when checking or building is slow. Long `do`
  blocks (measured), type-level computation, search, ambiguity, `--jobs`, TTC reuse,
  C compile time.
- `cases/`: W0007 with and without the fix.

## Rules of thumb that hold here

- Measure with `perf stat -e instructions:u` before and after a change; keep a change
  only if the count drops.
- A hot loop should be a tail-recursive function over `Int`/`Double`/`Bits64`
  arguments with no `Integer`, no `IORef`, no interface method of unknown type and no
  string indexing. Such a loop costs a few instructions per iteration (a sum over
  `Int` measured 8).
- Name every local value that is used more than once with `let`, not `where`, when it
  depends on the function's arguments.
- Give literals a type in long `do` blocks, and keep `do` blocks short.
