---
name: idris2i-1
description: Use for any Idris2i-1 work - writing, fixing, reviewing, explaining or porting `.idr` and `.ipkg` code, reading compiler errors (codes like E0201), filling holes, running the compiler or REPL, building executables and packages. Load it before writing the first line of Idris2i-1, even a short function - Idris2i-1 is not Haskell and not Idris 1, and this compiler differs from upstream Idris 2 (C back end by default, error codes with `--explain`, stricter totality, new libraries).
---

# Writing Idris2i-1

Idris2i-1 looks like Haskell and behaves differently in dozens of small ways; code
written from Haskell or Idris 1 habit fails to parse or to type-check. Two things make
the work go well: let the compiler answer questions instead of guessing, and check
after every small step.

<!-- idris
import Data.List
import Data.String
import Data.Vect
import System
import System.File
-->

## The compiler and the helper scripts

`scripts/` in this skill's directory:

| Script | Use |
|---|---|
| `idr-find` | prints the path of the compiler (`$IDRIS2I_1`, a compiler checkout around you, `idris2i-1` on `PATH`, `~/.idris2i-1/bin/idris2i-1`) |
| `idr-check FILE...` | type-checks, then lists the holes that are left |
| `idr-q [FILE] ':t x' ':doc y' 'expr'` | asks the REPL several things in one run |

Below, `idris2i-1` means the path that `idr-find` prints. It is often not on `PATH`.

## Working loop

1. **Write the types first**, then one definition at a time. Put a hole (`?name`) where
   you do not know the expression yet; a file with holes still checks.
2. **Check after each definition**: `idr-check File.idr` (inside a package it picks up
   the `.ipkg`). A whole file written before the first check fails in ten places at
   once, and the first error hides the rest.
3. **Read the error before editing.** The first line ends in a code such as `[E0201]`;
   lines after the source excerpt carry `Suggestion:` or `Did you mean:` and are often
   the fix. `idris2i-1 --explain E0201` gives the meaning, an example and the usual fixes.
   Fix the first error, check again. A parse error on a line that looks right is very
   often a keyword used as a name: `total`, `default`, `proof`, `data`, `record`.
4. **Ask instead of guessing.** For a library function: `idr-q ':module Data.String'
   ':doc split'`, `':search List a -> Maybe a'`, `':browse Data.SortedMap'`. For a hole:
   `idr-q File.idr ':t name'` shows every variable in scope and the type needed. A
   Haskell name may not exist here, or exist with another type.
5. **Let the compiler write code** when the types determine it: `:cs LINE COL var`
   splits a clause into cases, `:ac LINE fn` writes the first clause, `:gd LINE fn`
   proposes a whole definition (see `references/toolchain.md`).
6. **Finish**: `idr-check` reports `ok, no holes`, the program was built and run on a
   real input, and nothing was silenced with `believe_me`, `assert_total` or
   `idris_crash` without a reason you can state.

## A complete program

```idris
||| Number of lines, words and characters.
count : String -> (Nat, Nat, Nat)
count s = (length (lines s), length (words s), length s)

covering                                   -- readFile loops on input: not `total`
main : IO ()
main = do
  [_, path] <- getArgs                     -- the program name comes first
    | _ => die "usage: wc FILE"
  Right text <- readFile path              -- Either FileError String
    | Left err => die "wc: \{path}: \{show err}"
  let (l, w, c) = count text
  putStrLn "\{show l} \{show w} \{show c}"
```

```sh
idris2i-1 Wc.idr -o wc        # C back end by default; needs a C compiler
./build/exec/wc notes.txt
idris2i-1 Wc.idr --exec main  # or: compile and run once
```

For more than one module or any dependency outside `base`, write an `.ipkg`
(`references/project.md`).

## What differs from Haskell

Each line was confirmed with this compiler; `references/traps.md` has the error message
for each wrong form.

**Syntax**

- Signatures use one colon, `f : Int -> Int`; `::` is list cons. Every top-level
  definition needs a signature, and so does every local function in a `where`.
- Lambdas and case alternatives use `=>`: `\x => x + 1`, `Just v => v`.
- No guards. Use `if ... then ... else` (the `else` is required), `case`, or `with`.
- `interface` and a bare implementation head (`Show Colour where`), not `class` and
  `instance`. No `newtype` or `type`: a synonym is a function returning `Type`, with a
  capitalised name. No `deriving` clause: `Eq`, `Ord`, `Show` are derived with
  `%runElab derive` (`references/syntax.md`) or written by hand.
- Record update is `{ field := v } r` and `{ field $= f } r`; projection is `r.field`.
- Type annotation inside an expression: `the Nat 3`. The list type is `List a`.
- Definitions are read top to bottom. For mutual recursion, write the signatures first.
- Imports come before any declaration. Module `A.B` lives in `A/B.idr`.
- `total`, `default`, `proof`, `auto`, `open`, `prefix`, `data`, `record`, `using` are
  keywords. `let total = ...` gives `Not the end of a block entry, check indentation`
  or `Couldn't parse any alternatives`, sometimes on a nearby line; call it `sumAll`.

**Names**

- `pure`, not `return`. `traverse_`/`for_` and `traverse`/`for`, not `mapM_`/`forM`.
- `printLn x` prints a line (`print` adds no newline). `<+>` is the semigroup operator.
- No `read`, `fromIntegral`, `error`, `undefined`, `otherwise`, `seq`, `!!`, `^`:
  `parsePositive`/`parseInteger`, `cast`, an `Either` result, a hole, `True`, nothing
  (evaluation is strict), `getAt`, `power`. Bit operations (`.&.`, `.|.`, `xor`,
  `shiftL`, `shiftR`) and `fromMaybe` exist after `import Data.Bits`, `import Data.Maybe`.
- There is no `Data.Char`, `Data.Foldable` or `Data.Ord`: `isDigit`, `isAlpha`, `ord`,
  `chr`, `traverse_`, `comparing` are in the Prelude.
- `head`, `tail`, `foldl1` want a proof that the list is non-empty; match on the list
  or use `head'`, `last'`. There is no `maximum` for lists: `foldl max start xs`.
- Maps and sets are `Data.SortedMap` and `Data.SortedSet`.

**Types**

- `String` is primitive, not a list: `unpack`/`pack` convert, `strUncons` takes the
  first character, `++` concatenates. Interpolation `"\{e}"` needs `e : String`, so
  write `"\{show n}"`.
- An integer literal is an `Integer` unless the context says otherwise. `Int` is the
  machine integer. `length` returns `Nat`. Nothing converts implicitly: use `cast`.
- `Nat` has no `-` (use `minus`, `pred`, or match on `S k`) and `/` is only for
  `Double` (use `div`, `mod`; on `Nat` they need `import Data.Nat`).
- A tuple `(a, b, c)` is the nested pair `(a, (b, c))`.
- A range counts down when the end is smaller: `[1 .. 0]` is `[1, 0]`, not empty.
- With `Data.Vect` imported, a literal `[1, 2, 3]` may be a `List` or a `Vect`; when
  the compiler says `Ambiguous elaboration`, write `the (List Int) [1, 2, 3]`.

**Semantics**

- Evaluation is strict. `Lazy a` delays an argument; `if`, `&&`, `||` are lazy already.
- IO functions are `HasIO io => ... -> io a` and report failure as a value:
  `readFile : String -> io (Either FileError String)`. There are no IO exceptions.
  A statement in a `do` block whose result is not `()` must be bound or ignored:
  `ignore (fPutStrLn stderr msg)`; left bare it fails with "Can't find an
  implementation for HasIO ?io".
- Everything is private unless marked `export` (name and type) or `public export`
  (also the definition). A function or synonym that appears in the types of other
  modules must be `public export`, or those types will not compute.

## Implicit arguments and erasure

A lowercase name in a signature that is not bound becomes an implicit argument, and it
is erased: it exists for the type checker only.

```idris
failing "n is not accessible in this context"
  len : Vect n a -> Nat
  len xs = n

len : {n : Nat} -> Vect n a -> Nat         -- bound in braces: kept at run time
len xs = n
```

This also means a lowercase definition cannot be used in a type by its bare name: in
`Vect size Int`, `size` is a fresh variable (warning W0003), whatever `size` you
defined. Capitalise such constants or qualify them. In a hole's context, `0` in front
of a variable marks it erased, `1` linear (must be used exactly once).

## Totality

Each definition is `total` (all inputs handled, always terminates), `covering` (all
inputs handled; the default) or `partial`. `%default total` at the top of a file asks
for total everywhere, and is good practice for libraries.

- Missing clauses are an error at every level except `partial`; the message lists them.
- Under `total`, recursion must be on a visible part of an argument (`f (x :: xs)`
  calling `f xs`). Calling `f (filter p xs)` or recursing through `map` is rejected.
- `div` and `mod` are not total, so a `total` function using them is rejected (this
  fork): `divNatNZ n 2 %search`, or a checked divisor with `assert_total`.
- `readFile`, `getLine` loops and servers never get to be `total`: mark them and `main`
  as `covering`.

The `idris2i-1-proofs` skill covers what to do when the checker does not see termination.

## References

Read the one that matches the task; each is checked against the compiler.

| File | Read it when |
|---|---|
| `references/syntax.md` | you need the exact form of a construct: data, records, interfaces, implicits, `do`, strings, numbers, `with`, namespaces |
| `references/traps.md` | you are porting Haskell or Idris 1 code, or an error looks like a habit from another language |
| `references/errors.md` | an error is unclear: the common codes with cause and fix, and what to do when the message does not help |
| `references/toolchain.md` | you need a compiler or REPL command: holes, case splitting, search, JSON errors, options |
| `references/project.md` | setting up a package, dependencies, building, installing, golden tests, back ends |

Other skills: `idris2i-1-proofs` (proofs, totality, views, quantities), `idris2i-1-libraries`
(files, collections, concurrency, HTTP, JSON), `idris2i-1-ffi` (C and other foreign code),
`idris2i-1-performance` (slow programs, slow type checking), `idris2i-1-compiler-dev` (working
on the compiler itself).

## If the compiler is upstream Idris 2

This skill describes a fork. When `idris2i-1 --explain E0101` is not recognised, you have
upstream Idris 2: no error codes, no import suggestions, Chez Scheme as the default back
end (`--cg refc` selects C), `div`/`mod` accepted in total functions, no `http`, `tls`
or typed JSON libraries, and no `Deriving.Eq`/`Ord`/`DecEq`. The language rules above
hold on both.
