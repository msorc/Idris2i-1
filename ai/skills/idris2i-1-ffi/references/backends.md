# Foreign functions on each back end

<!-- idris
import Data.Buffer
-->

What differs between RefC (the default of this fork), Chez, Racket and JavaScript, and
the pragmas around `%foreign`. Everything marked "ran" was built and run with this
compiler; Racket was not installed, so its lines come from the FFI documentation.

| | RefC (default) | Chez (`--cg chez`) | Racket | Node / browser |
|---|---|---|---|---|
| specifiers | `RefC:`, `C:` | `scheme,chez:`, `scheme:`, `C__scoped_callbacks:`, `C:` | `scheme,racket:`, `scheme:`, `C:` | `node:` or `browser:`, then `javascript:` |
| C library | linked by `cc` (`%cg refc refc-...`), header required | `.so` loaded at run time | `.so` loaded at run time | none |
| `Int` | `int64_t` | `int` (truncates) | `int` | 32-bit `Number` |
| callback | an `Idris2i_1_Closure *` (glue applies it) | a C function pointer, kept for ever | a C function pointer, valid during the call only | a curried JS function |
| `Struct` | yes (this fork) | yes | not documented | not documented |
| `Buffer` | argument, as `char *` | argument, as `u8*`; not a result | argument | not checked |
| finaliser runs | at the last reference | at a collection or exit | supported (documentation) | not checked |

## RefC

- `"C:fn,lib,header.h"`: a C call. `String` is `char *`; integers and `Double` are C
  numbers; pointers are `void *`; a `Buffer` is `char *` to its bytes; a callback is an
  `Idris2i_1_Closure *`. The header is included in the generated C, which is compiled with
  `-Werror`, so a mismatch with the prototype is a build error. That is the check you
  get; use it (always name a header).
- `"RefC:fn"`: for C written against the runtime. A `String`, an `Integer` or a foreign
  object is an `Idris2i_1_Value *` (borrowed argument; a result is a new reference), while
  fixed width integers and `Double` are still C numbers. RefC prefers `RefC:` to `C:`,
  so the two can be given together for code that works with Idris2i-1 values on RefC and
  with C types elsewhere.
- A callback for a C function pointer needs glue: see the trampoline in
  `c-library.md`. Passing the closure where C wants a function pointer is a C error
  (`passing argument 4 of 'qsort' from incompatible pointer type`), not a crash.
- A foreign function cannot return a function: `The foreign function
  Main.prim__getTwice returns a function, which the RefC backend does not support: return
  a Ptr or AnyPtr instead`.
- RefC does not reject a foreign function that returns `GCAnyPtr` (Chez does: `Can't
  return GCPtr from a foreign function`); the value is not a GC pointer. Return
  `AnyPtr` and call `onCollectAny`.
- Linking (`refc-lib`, `refc-archive`, `refc-pkg-config`, `IDRIS2I_1_*FLAGS`): `SKILL.md`.
  In a package, the same directives go in `opts` of the `.ipkg` or in a `%cg refc` line
  of a module; a package that ships C copies its archive and header into its installed
  `lib` directory (in the compiler repository: "Linking C libraries" in
  `docs/source/ffi/ffi.rst`, and `libs/tls`, which binds OpenSSL this way).

## Chez

- `"C:fn,libfoo"` loads `libfoo.so`; `"C:fn,libfoo 3"` loads `libfoo.so.3`; a name with
  a dot is used as it is. The library is looked for at build time in the current
  directory, `IDRIS2I_1_LIBS` and the `lib` directories of packages, and copied into
  `build/exec/prog_app/`, whose launcher script sets `LD_LIBRARY_PATH`. A `C:` specifier
  without a library is refused: `The given specifier '["C:abs"]' was not accepted by any
  backend` (E1301).
- `"scheme:expr"` is any Scheme expression applied to the arguments, and
  `--directive extraRuntime=file.ss` (or `%cg chez extraRuntime=file.ss`) adds Scheme
  definitions to the program.
- `Int` is a C `int`: `labs` of `-2^40` declared `Int -> Int` returned `0` (RefC gave
  `1099511627776`). Use `Int64` for 64 bits.
- A callback becomes a C function pointer that stays valid for ever: its code is locked
  and never freed, about 350 bytes per call that passes one (documentation). For a C
  function that only calls the callback before it returns, `C__scoped_callbacks` (this
  fork) frees it after the call. It ran with Chez:

```idris
namespace Sort
  %foreign "C__scoped_callbacks:qsort,libc" "C:qsort,libc"
  prim__qsort : Buffer -> Bits64 -> Bits64 -> (AnyPtr -> AnyPtr -> Int) -> PrimIO ()

  -- read the int32_t that a pointer points to
  %foreign "scheme,chez:(lambda (p) (foreign-ref 'integer-32 p 0))"
  readInt32 : AnyPtr -> Int32

  cmp : AnyPtr -> AnyPtr -> Int
  cmp a b = case compare (readInt32 a) (readInt32 b) of
    LT => -1
    EQ => 0
    GT => 1

  export
  sortDemo : IO ()
  sortDemo = do
    Just buf <- newBuffer 16 | Nothing => pure ()
    traverse_ (\(i, v) => setInt32 buf i v) [(0, 30), (4, 10), (8, 40), (12, 20)]
    primIO $ prim__qsort buf 4 4 cmp
    printLn !(traverse (getInt32 buf) [0, 4, 8, 12])
```

```text
[10, 20, 30, 40]
```

With RefC the same declaration is a C error (the closure is not a function pointer).

- A callback with user data, where the C library passes the `void *` back: with Chez
  the callback has the C signature, user data included. This one ran with Chez against
  a C function `int64_t lib_sum(int64_t n, int64_t (*f)(void *, int64_t), void *ud)` in
  `libcb.so` (the `ud` argument was not given here, so it is not used):

```idris
namespace ChezCallback
  %foreign "C:lib_sum,libcb"
  prim__libSum : Int64 -> (AnyPtr -> Int64 -> Int64) -> PrimIO Int64

  export
  sumSquares : IO Int64
  sumSquares = primIO $ prim__libSum 10 (\_, x => x * x)    -- 385
```

- A `String` or `Buffer` argument is locked during the call, so a collection inside a
  callback does not move it (documentation). A `Buffer` cannot be returned.
- A segfault in C becomes a Scheme error ("invalid memory reference") with a backtrace
  that lacks the C frames; a `NULL` returned as `String` fails later, where it is used:
  `Exception in string-append: #f is not a string`.

## Racket (from the documentation)

The same `C:` specifiers, plus `scheme,racket:`. A callback is valid only during the
call: a library that keeps it may later call code that was collected. `String` and
`Buffer` arguments are not locked, so a C function that calls back into Idris2i-1 may see
them move.

## JavaScript: Node and the browser

`"node:lambda:js"`, `"browser:lambda:js"` (exclusive) and `"javascript:lambda:js"`
(both); the code is a JavaScript expression, usually an arrow function, applied to the
arguments. `"node:support:fn,file"` calls `file_fn` from `file.js` in a `js` directory of
a package's data. A `C:` specifier means nothing here (`No supported backend found in the
definition of Main.prim__puts. Supported backends: "node","javascript"`), so give a
JavaScript specifier next to it.

```idris
namespace Js
  %foreign "C:labs,libc,stdlib.h"
           "scheme:abs"
           "javascript:lambda:x => Math.abs(x)"
  absInt : Int -> Int

  %foreign "javascript:lambda:x => typeof x"
  typeOfBits64 : Bits64 -> String

  -- an Idris function of two arguments is curried in JavaScript
  %foreign "javascript:lambda:(f, x) => f(x)(x)"
  applyTwice : (Int -> Int -> Int) -> Int -> Int

  -- an effectful callback takes its arguments, then the world
  %foreign "javascript:lambda:(f, w) => f(5)(w)"
  prim__withFive : (Int -> PrimIO ()) -> PrimIO ()

  %foreign "node:lambda:(s, w) => console.log('node says ' + s)"
  prim__log : String -> PrimIO ()
```

With Node these gave `7` for `absInt (-7)`, `bigint` for `typeOfBits64 1`, `8` for
`applyTwice (+) 4`, and `prim__withFive (\n => toPrim (printLn n))` printed `5`. A
`PrimIO` function takes the world as its last JavaScript argument (`w`). `Int8` to
`Int32`, `Bits8` to `Bits32`, `Int` and `Double` are `Number`; `Int64`, `Bits64` and
`Integer` are `BigInt`; `String` is a string; anything else goes through `AnyPtr`.

## Pragmas around `%foreign`

- `%foreign_impl Name "spec"` adds a specifier to a `%foreign` of another module (or of
  this one), for a back end that it does not cover. It ran with Node:

```idris
namespace Impl
  %foreign "C:labs,libc,stdlib.h"
  cabs : Int -> Int

  %foreign_impl Main.Impl.cabs "javascript:lambda:x => Math.abs(x)"
```

- `%export "javascript:addInts"` gives an Idris2i-1 function a name in the generated
  JavaScript, which JavaScript code (another `%foreign`) can call. The documentation
  says that only the JavaScript back ends support it; C code reaches Idris2i-1 through
  callbacks.

```idris
namespace Export
  %export "javascript:addInts"
  addInts : Int32 -> Int32 -> Int32
  addInts a b = a + b
```

- `%nomangle` is deprecated in favour of `%export`.
- Several specifiers: one per line, or (this fork) after a string literal on the same
  line; see `SKILL.md`.
