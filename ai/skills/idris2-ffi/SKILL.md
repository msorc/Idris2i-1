---
name: idris2-ffi
description: Use when Idris 2 code calls C or other foreign code - `%foreign`, binding or wrapping a C library (sqlite, curl, SDL, zlib, OpenSSL...), calling a libc function, linking a `.so`/`.a` or a glue `.c` file with RefC (`%cg refc refc-lib=`, `refc-pkg-config=`, `IDRIS2_CFLAGS`/`IDRIS2_LDLIBS`), `Ptr`/`AnyPtr`, `Struct`, `Buffer`, callbacks, `PrimIO`/`primIO`, finalisers (`onCollect`), who frees a string, JavaScript `%foreign "node:lambda:..."`, or a segfault or C compiler error at the FFI boundary.
---

# Calling C from Idris 2

<!-- idris
import Data.Buffer
import System.FFI
-->

There is no `foreign import ccall` (Haskell) and no `foreign FFI_C` (Idris 1). A foreign
function is a `%foreign` declaration: one or more *specifier* strings, then a type with
no body. The compiler cannot see C: it trusts the type you write, and a wrong type is a
crash or garbage at run time, never a type error.

The default back end of this compiler is **RefC** (this fork): it writes C, includes the
headers that the specifiers name, and runs `cc` with `-Werror`. So the C compiler checks
each call against its header, and much of what goes wrong shows up as a C error while
building. `--check` does none of this: build and run every binding (`idris2 -o prog
Main.idr && ./build/exec/prog`). `--cg chez` loads shared libraries when the program runs.

## The shape of a binding

```idris
-- A pure C function: no effects, same result for the same arguments.
%foreign "C:cos,libm 6,math.h"
cos' : Double -> Double

-- An effectful one: its result is PrimIO, and a wrapper lifts it to any HasIO.
%foreign "C:puts,libc,stdio.h"
prim__puts : String -> PrimIO Int32

puts : HasIO io => String -> io Int32
puts s = primIO (prim__puts s)
```

`"C:name,library,header"`: RefC includes the header (`#include <math.h>`) and ignores the
library; Chez loads the library (`libm 6` is `libm.so.6`) and ignores the header. Write
both so that one declaration works with both. Call the raw function `prim__x`, keep it
private, and export the `HasIO io =>` wrapper: callers then use it in `IO` or in any monad
with `HasIO`. A callback written in `IO` goes to C through `toPrim` (see
`references/c-library.md`).

## Pure or `PrimIO`

Give a foreign function a pure type only when the C function is pure. The compiler
treats a pure call like any other expression: it drops one whose result is unused, and a
definition without arguments is computed once and kept:

```idris
namespace PureBug
  %foreign "C:puts,libc,stdio.h"
  putsPure : String -> Int

  demo : IO ()
  demo = do
    let n = putsPure "first"      -- never printed: n is unused
    putStrLn "second"
    let m = putsPure "third"
    printLn m
```

```text
second
third
6
```

(RefC and Chez the same.) Likewise `seed = randPure` gave the same number at every use.
Anything that reads or changes state (I/O, `errno`, a handle, memory, the clock) returns
`PrimIO t`. Write `PrimIO Int`, not `IO Int`: `IO` is not an FFI type (Chez: "Can't pass
argument of type PrimIO.IO Int to foreign function"; RefC: a C error).

## Specifiers

| Back end | Specifiers it takes, in its order of preference |
|---|---|
| RefC (default) | `"RefC:fn"` (Idris values, for runtime code), `"C:fn,lib,header.h"` |
| Chez (`--cg chez`) | `"scheme,chez:expr"`, `"scheme:expr"`, `"C__scoped_callbacks:fn,lib"`, `"C:fn,lib"` |
| Racket | `"scheme,racket:expr"`, `"scheme:expr"`, `"C:fn,lib"` |
| Node, browser | `"node:lambda:js"`, `"browser:lambda:js"`, `"javascript:lambda:js"`, `"node:support:fn,file"` |

A back end picks by its own order, not by the order you wrote: with `"C:getenv,..."`
first and `"scheme:..."` second, Chez still runs the Scheme one. Language names are
case-sensitive (`"c:abs"` matches nothing). Details per back end, `%foreign_impl` and
`%export`: `references/backends.md`.

Several specifiers go one per line, lined up; or (this fork) a string literal followed
by more on the same line. A function that builds specifiers saves repetition, but after a
non-literal the rest of the line is its arguments:

```idris
namespace Specs
  libc : String -> String
  libc fn = "C:" ++ fn ++ ",libc,stdlib.h"

  %foreign libc "labs"
           "scheme:abs"
  abs1 : Int -> Int

  %foreign "scheme:abs" libc "labs"
  abs2 : Int -> Int

  failing "Mismatch between: String and ?argTy -> String"
    %foreign (libc "labs") "scheme:abs"
    abs3 : Int -> Int
```

When no specifier fits, the build stops (`--check` says nothing): Chez reports
`The given specifier '["C:abs"]' was not accepted by any backend` (E1301; `"C:abs"` has
no library), RefC `INTERNAL ERROR: [refc] FFI not found for Main_cabs`, Node `No supported
backend found in the definition of Main.prim__puts`.

## Types at the boundary

| Idris | C (RefC) | Notes |
|---|---|---|
| `Int` | `int64_t` | `int` with Chez (2^40 came back as 0) and 32 bits with JavaScript |
| `Int8`..`Int64`, `Bits8`..`Bits64` | `int8_t`..`uint64_t` | the same everywhere: prefer them (`Int32` for `int`) |
| `Double`, `Char` | `double`, `char` | |
| `String` | `char *` | see ownership below |
| `Ptr t`, `AnyPtr` | `void *` | `t` is only a label for Idris |
| `GCPtr t`, `GCAnyPtr` | `void *` | argument only; made by `onCollect`/`onCollectAny` |
| `Buffer` | `char *` to its bytes | RefC: only for `char`/`unsigned char`/`void` pointers; Chez cannot return one |
| `Struct "n" [fields]` | pointer to a `struct` | `System.FFI`, see `references/c-library.md` |
| `a -> b` | a callback | RefC passes an `Idris2_Closure *`, not a function pointer |
| `()` | `void` | result only |

`Integer`, `Nat`, `Bool`, `List`, records and data types do not cross. Chez rejects them
(`Can't pass argument of type Prelude.Basics.Bool to foreign function`); RefC passes the
Idris value and only the C compiler notices (`makes integer from pointer without a
cast`). Convert first: a `Bool` as `Int32`, a `Nat` as `Bits64` (`cast`).

A type alias (`Handle = AnyPtr`) may appear in a foreign type if it unfolds there; one
declared in a `namespace` block must be `public export`, or `--check` stops with
`Can't marshal type for foreign call Main.N.Handle`.

RefC compiles with `-Werror`, so a C function returning `const T *` does not fit `Ptr t`
or `AnyPtr` (`initialization discards 'const' qualifier`), and a `Buffer` cannot be a
`uLong *`. Write a one-line C wrapper with a cast (`references/c-library.md` does), or for
a pointer that C writes into, use a one-field `Struct` (below). `String` results may be
`const char *`.

## Strings and memory: who owns what

- A `String` argument is a `char *` into the Idris string, valid until the call returns.
  C must not change or free it; a library that keeps it must copy it (SQLite: bind with
  `SQLITE_TRANSIENT`, a macro, so through glue).
- A `String` result is copied, and the `char *` is never freed. Right for a string the
  library keeps (`getenv`, `strerror`, `sqlite3_errmsg`); a leak for one the caller must
  free; a crash for `NULL` (RefC: SIGSEGV in the call; Chez: `#f is not a string` later).
- A string that may be `NULL` or that the caller frees is a `Ptr String`: test it, copy
  it in IO, then free it. The copy must be an IO action, not the pure `prim__getString`,
  so that it surely happens before the free:

```idris
namespace OwnedString
  %foreign "C:strdup,libc,string.h"
  prim__strdup : String -> PrimIO (Ptr String)

  %foreign "C:idris2_getString,libidris2_support,idris_support.h"
  prim__copyString : Ptr String -> PrimIO String

  duplicate : HasIO io => String -> io (Maybe String)
  duplicate s = do
    p <- primIO (prim__strdup s)
    if prim__nullPtr p /= 0 then pure Nothing else do
      copy <- primIO (prim__copyString p)
      free (prim__forgetPtr p)            -- System.FFI.free is C's free
      pure (Just copy)
```

- A `Ptr`/`AnyPtr` is not managed. Free it yourself, or wrap it with
  `onCollectAny p fin` (an `IO GCAnyPtr`). With RefC the finaliser runs as soon as the
  last reference goes, which may be in the middle of `main`; with Chez at a collection
  or when the program exits. Keep the `GCAnyPtr` alive (use it) for as long as C uses the
  raw pointer.
- A `Buffer` (`Data.Buffer`, `newBuffer n`) is memory that Idris owns and C fills or
  reads during the call: the way to pass bytes both ways.

## Linking

**RefC** (this fork's directives; the C compiler runs when you build):

- Every C function needs a header in its specifier: without one GCC 14 stops with
  `implicit declaration of function`. Headers are looked for in the runtime's directories,
  in `./lib` and the `lib` directories of packages, and where `IDRIS2_CFLAGS` says
  (`-I.`); the current directory is not searched.
- Say what to link in the module that binds the library, so that every program importing
  it gets it: `%cg refc refc-pkg-config=sqlite3` (cflags and libs from pkg-config),
  `%cg refc refc-lib=ssl crypto` (`-lssl -lcrypto`), `%cg refc refc-archive=glue.o`
  (a `.a` or `.o` found in `./lib`, the current directory, the packages' `lib`
  directories or `IDRIS2_LIBS`). The same works as `--directive refc-lib=foo`. A wrong
  one is an error naming it (`refc-lib=-lglue`, `refc-libs=`, a missing archive).
- `IDRIS2_CFLAGS`, `IDRIS2_CPPFLAGS`, `IDRIS2_LDFLAGS`, `IDRIS2_LDLIBS` (falling back to
  `CFLAGS`...) add flags: `IDRIS2_LDFLAGS=-L/opt/foo/lib`.
- Your own C goes in a glue file compiled to an object; `refc-archive` links it. Glue
  that touches Idris values includes `runtime.h`: `cc -c -fPIC -I"$(idris2
  --libdir)/support/refc" glue.c -o lib/glue.o`.
- A shared library must be found when the program runs: `LD_LIBRARY_PATH`, or link with
  `IDRIS2_LDFLAGS="-L$PWD -Wl,-rpath,$PWD"`. Otherwise: `error while loading shared
  libraries: libtw.so: cannot open shared object file`.

**Chez**: `"C:fn,libfoo"` loads `libfoo.so`. A file found at build time (current
directory, `IDRIS2_LIBS`, package `lib` directories) is copied next to the program in
`build/exec/prog_app/`, so it runs from anywhere; one not found is loaded by name at run
time and fails then (`Exception: (while loading libtw.so) ... cannot open shared object
file`). On glibc `libm.so` and `libc.so` are linker scripts (`invalid ELF header`): give
the version, `"C:cos,libm 6"` (`libm.so.6`).

## Callbacks and structs, in short

A function argument (`(Int -> Int)`, or `(Int -> PrimIO Int)` for an effectful one) is a
real C function pointer with Chez, but with RefC C receives the closure as an
`Idris2_Closure *`. A C library that wants a function pointer therefore needs a small
trampoline in glue C that applies the closure with `idris2_apply_closure`, usually
through the library's `void *userdata`. A worked one, with reference counts:
`references/c-library.md`. Call callbacks only on the thread that called C.

`Struct "name" [("field", Type), ...]` is a pointer to a C struct; `getField` (pure) and
`setField` (IO) read and write it; it works with RefC (this fork) and Chez. List every
field, in order: Idris computes the layout. In a `Struct` `Int` is a C `int` (not the
`int64_t` of an argument). Allocate with a `calloc` bound to return the struct type. A
struct of one field is a cell for an out-parameter: `Struct "len_cell" [("n", Bits64)]`
passed where zlib's `compress` wants a `uLong *` ran with RefC and Chez, and
`[("p", AnyPtr)]` takes an `sqlite3 **`.

## A segfault or a strange value: checklist

1. Build with `--directive refc-backtrace` (or run with `IDRIS2_REFC_BACKTRACE=1`): a
   crash then prints `RefC: segmentation fault (SIGSEGV)` and the Idris functions, instead
   of only exit status 139.
2. Each Idris type against the C prototype: `Int` vs `int` (Chez), a missing argument, a
   `Struct` with a missing or reordered field, a pointer to a pointer.
3. A `String` result that can be `NULL` (`getenv`, a column, an error message): make it
   `Ptr String` and test with `prim__nullPtr`.
4. A pure type on an effectful function (dropped or repeated calls).
5. Memory freed twice, or used after free: a finaliser that frees what C or another
   handle still uses (RefC finalises early), a `String` argument kept by C, a pointer read
   with pure `getField` after its cell was freed.
6. A callback that C keeps after the call returns (RefC: the closure is only borrowed;
   take a reference with `idris2_newReference`; Racket: never keep one), or that a thread
   started by C calls.
7. Run under `valgrind`; `IDRIS2_REFC_LEAKCHECK=1` reports Idris values that leaked.

## References

- `references/c-library.md`: a complete SQLite binding with glue C: opaque handles,
  out-parameters, strings both ways, errors as `Either`, a callback trampoline,
  finalisers, blobs through `Buffer`, a libc `struct tm`, and the build commands. Read it
  before wrapping any real library.
- `references/backends.md`: RefC, Chez, Racket and JavaScript side by side: specifiers,
  callbacks, structs, buffers, `%foreign_impl`, `%export`, `C__scoped_callbacks`.
