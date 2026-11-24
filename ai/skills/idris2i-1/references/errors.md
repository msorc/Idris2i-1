# Reading compiler errors

## The shape of an error

```text
Error: While processing right hand side of sorted. Undefined name sortBy. [E0201]

Foo:10:13--10:19
 09 | sorted : List Nat -> List Nat
 10 | sorted xs = sortBy compare xs
                  ^^^^^^
Suggestion: Data.List exports sortBy; add import Data.List.
```

- First line: where the checker was, what went wrong, and the code.
- `Module:line:col--line:col`, counted from 1, then the source with the place marked.
- After the source: `Suggestion:`, `Did you mean:`, `Possible correct results:` or the
  list of candidates. Read these before changing code; they often are the fix.
- `idris2i-1 --explain E0201` prints what the code means, an example, and the usual fixes
  (this fork). Do this the first time you meet a code.

`Expected` is what the context needs, `Got` is what the expression has. A name like
`?a` or `?_{1}` is something the checker had not worked out yet.

Fix the first error first. One mistake in a signature produces errors in every
definition that uses it, and a parse error hides everything after it.

## Codes you will meet

Each row has a file in `cases/` that produces exactly this code.

| Code | Headline | Usual cause | Fix |
|---|---|---|---|
| E1101 | `Couldn't parse declaration`, `Expected '=>'`, `Expected 'else'`, `Expected end of input` | Haskell syntax: `::` signature, `->` in a lambda or `case`, a guard, `if` without `else`; or wrong indentation | see the table in `traps.md`; continuation lines must be indented more than the start of the definition |
| E0000 | `Unknown operator '!!'` | an operator that does not exist (`!!`, `<>`, `^`) or whose module is not imported (`.&.` needs `Data.Bits`) | `getAt`, `<+>`, `power`; import the module that declares it |
| E0201 | `Undefined name x` | missing import, a Haskell name, use before declaration, or a typo | take the `Suggestion`; `traps.md` lists replacements; declare before use |
| E0205 | `No type declaration for Main.type` | a definition without a signature; also `type`, `newtype`, `codata` used as keywords | add the signature; a synonym is `Name : Type` and `Name = String` |
| E0101 | `Mismatch between: Nat and Int` | two different types; numbers are never converted silently | `cast`; fix the signature; `show` for strings |
| E0101 | `Mismatch between: S ?len and size` after warning W0003 | a lowercase name in a type was bound as a new variable | capitalise or qualify the name |
| E0102 | `Can't solve constraint between: 2 and two` | a definition used in a type does not reduce: it is only `export`, or it is stuck on a variable | `public export`; or prove the equation (the `idris2i-1-proofs` skill) |
| E0202 | `Name M.secret is private` | no `export` on the definition | `export`, or `public export` |
| E0301 | `Ambiguous elaboration. Possible results:` | an overloaded name or literal and nothing to choose by; typically `[1, 2]` with `Data.Vect` imported | `the (List Int) [...]`, a qualified name, a type on the binding |
| E0302 | `Sorry, I can't find any elaboration which works. All errors:` | every reading of an overloaded name failed | find the candidate you meant in the list (`If Prelude.List.length: ...`) and fix that error |
| E0401 | `Can't find an implementation for Eq T` | no implementation for your type, or one exists in a module you did not import | write the implementation; add the constraint `Eq a =>` to the signature; import |
| E0401 | `Can't find an implementation for Integral Nat` | `div`/`mod` on `Nat` without the module | `import Data.Nat` |
| E0401 | `... Neg Nat`, `... Fractional Int`, `... FromString T`, `... Num (a -> b)` | `-` on `Nat`; `/` on integers; a string literal where another type is expected; a function where a number is expected | `minus`/`pred`; `div`; build the value; check the number of arguments |
| E0401 | `Can't find an implementation for NonEmpty xs` | `head`, `tail`, `foldl1` on a list not known to be non-empty | pattern match, or `head'` |
| E0501 | `Unsolved holes:` | a type the checker could not work out, such as the element type of `[]` | `the (List Int) []`, or a signature |
| E0601 | `f is not covering.` with `Missing cases:` | a constructor or combination without a clause; applies to implementations too | add the clauses printed; for cases that cannot happen write `f x impossible` |
| E0602 | `f is not covering.` with `Calls non covering function` | a `total` function calls a partial one; `div` and `mod` count (this fork) | `divNatNZ`/`modNatNZ`; check and `assert_total`; or declare the function `covering` |
| E0703, E0704 | `f is not total, possibly not terminating due to ...` | recursion the checker cannot see getting smaller; a call to a non-terminating function such as `readFile` or an input loop | recurse on a part of an argument; `covering` for `main` and IO loops; techniques in the `idris2i-1-proofs` skill |
| E0606 | `Can't match on On (Erased argument)` | matching on a `0` argument | bind the argument without `0` |
| E0802 | `n is not accessible in this context` | an erased variable (an implicit, or a `0` argument) used at run time | bind it in the type: `{n : Nat} ->` |
| E0801 | `There are 0 uses of linear name x` | a `1` argument used zero or several times | use it exactly once, or drop the `1` |
| E1201 | `Module Data.Map not found` | the module does not exist here, or its package is not added | `Data.SortedMap`; `-p contrib` or a `depends` line |
| W0003 | `We are about to implicitly bind the following lowercase names` | a lowercase global used in a type | capitalise or qualify the name |
| W0002 | `Unreachable clause` | an earlier clause already matches; often a lowercase "constant" in a pattern, which is a variable | match on constructors; compare with `==` |

Not every message has its own code yet; a few report E0000, among them
`Module name A.B does not match file name` (run the compiler from the source
directory, or use `--find-ipkg`).

## When the message does not make sense

- **The error is in a line that looks right.** Check the signature it is checked
  against, and the definitions above it: a wrong implicit binding or a missing
  `public export` upstream shows up downstream.
- **`Type -> Type` versus `Type` on a `data` line.** There is a Haskell `deriving`
  clause; derive with `%runElab derive` instead (`syntax.md`).
- **A huge list of candidates.** An operator or literal is overloaded (`::`, `length`,
  `map`, `[]`). Add `the T (...)` around the smallest expression, or split the line
  into `let` bindings with types, and check again.
- **A mismatch between two types that print the same.** Run with `--show-implicits`;
  the implicit arguments differ.
- **`?_` or `?len` in the message.** The checker could not determine that part. Give
  it: an explicit implicit argument (`f {n = 3}`), or a signature on a local binding.
- **`Can't infer type for case scrutinee`.** A pattern-matching `let` or `<-`
  (`let Just xs = traverse parse args | Nothing => ...`) on an expression whose type
  is not fixed yet. Say it: `let Just xs = the (Maybe (List Double)) (traverse parse args)`.
- **A parse error on a line that looks right.** A keyword is used as a name (`total`,
  `default`, `proof`, `data`, `record`, `open`), or the line above is not finished.
- **It checks but you are not sure it is right.** Evaluate examples:
  `scripts/idr-q File.idr 'function arg'`.
