---
name: idris2-proofs
description: "Use when an Idris 2 task involves proofs or dependent types: equality (`Refl`, `rewrite`, `cong`, `sym`, `replace`), proving lemmas about Nat, List or Vect, index arithmetic in `Vect (n + m)`, `Dec`/`decEq`/`DecEq`, deriving Eq/Ord/DecEq, `solveNat`, `Uninhabited`/`impossible`/`Void`, `with` and views, well-founded recursion; totality and termination errors ('not total', 'not covering', 'possibly not terminating', 'not strictly positive', E0601-E0704), including `total` code that uses `div`/`mod`; erased or linear quantities (`0`/`1`, 'is not accessible in this context', 'Can't match on ... (Erased argument)', linear name errors, E0606/E0801/E0802, `-@`, `LIO`). Also use for 'make this function total' and 'Can't solve constraint between' in a proof."
---

# Proofs, totality and quantities in Idris 2

This builds on the `idris2` skill (finding the compiler, the `--check` loop,
`--explain CODE`, REPL one-shots, holes). It covers what that skill only summarises:
how to get a proof through, how to get a function accepted as total, and how to fix a
quantity error. Every example in these files is checked by the compiler.

<!-- idris
import Data.Nat
import Data.Nat.Solver
import Data.Vect
-->

What this compiler has for automation (details in `references/equality.md`):
`solveNat` (`Data.Nat.Solver`, `-p contrib`) proves equations of `Nat` built from
variables, literals, `S`, `+` and `*`; `Deriving.Eq`, `Deriving.Ord` and
`Deriving.DecEq` (base) derive those implementations. A user's installed compiler may
be older: if `:module Data.Nat.Solver` at the REPL says "Module Data.Nat.Solver not
found", it predates both, and proofs and `DecEq` are written by hand as below.
Elaborator scripts can also call `infer`, `quoteNF`, `convertible` and `getClauses`
(in the compiler repository: `docs/source/proofs/automation.rst`); this skill does not
teach writing them.

Still absent: tactics, solvers beyond `solveNat` (no ring over `Integer`, no omega for
`minus` or `LTE`), universe checking (`Type : Type` holds, so a proof that relies on
universe levels proves nothing here), and quantity polymorphism (only the eta-expansion
described under Quantities). Error codes and `--explain` are this fork's; upstream 0.8
prints messages without codes.

## Working method for a proof

**1. State the lemma so that it can be split.** Bind the variables you will induct on
explicitly, with their types:

```idris
total
plusZ : (n : Nat) -> n + 0 = n
plusZ Z = Refl
plusZ (S k) = cong S (plusZ k)
```

Two traps in the statement. An unbound `n` is an erased implicit, and erased values
cannot be matched (E0606, "Can't match on 0 (Erased argument)"); write `(n : Nat) ->`
or `{n : Nat} ->`. And without a type, `n` in `n + 0 = n` is not even a `Nat`: the
literal defaults it to `Integer` ("Mismatch between: Nat and Integer" when you split).
Mark lemmas `total`: a partial proof proves nothing.

**2. Leave holes and read the goals.** Write one clause per constructor with a named
hole on the right (`?base`, `?step`; pick names that are not library functions, as
`:t cons` also lists `Data.List1.cons`), then ask for each goal:

```sh
idris2 Proofs.idr --client ':t step'
```

```text
   k : Nat
   m : Nat
------------------------------
step : S (plus k m) = plus m (S k)
```

Goals show `+` as `plus` and `map` on lists as `mapImpl`. Names marked `0` in the
context are erased: usable in the proof, not at run time.

**3. Split on the argument that blocks evaluation.** `Refl` works when both sides
*evaluate* to the same term (definitional equality). A function evaluates only when the
argument it matches on is a constructor: `plus`, `++`, `minus` match on the first,
`map`, `length`, `reverse` on the list. So `0 + n = n` is `Refl`, `n + 0 = n` is not
("Can't solve constraint between: n and plus n 0", E0102): it needs a split on `n` and
induction. Splitting on the wrong variable leaves the goal stuck the same way.

**4. Close each goal.**

| The goal after the split | Close it with |
|---|---|
| both sides the same after evaluation | `Refl` |
| `C a = C b` (same constructor or function on both sides) | `cong C ih` |
| contains the left side of an equation you have | `rewrite ih in Refl` (or `in` a lemma) |
| contains the *right* side | `rewrite sym ih in ...` |
| an equation the other way round | `sym prf` |
| `Void`, or a case that cannot happen | `absurd prf`, an `impossible` clause |
| a long chain | `Calc $ \|~ a ~~ b ...(prf) ~~ c ...(prf')` (`Syntax.PreorderReasoning`) |
| an equation of `Nat` true by algebra alone (`+`, `*`, `S`, literals, variables) | `solveNat`, in a lemma with its own signature (below) |

`solveNat` needs no induction: it compares both sides as polynomials, so it also
proves what would take several `plus...` lemmas:

```idris
square : (a, b : Nat) -> (a + b) * (a + b) = a * a + 2 * a * b + b * b
square a b = solveNat

failing "the two sides are not equal as polynomials"
  wrongLaw : (n, m : Nat) -> n + m = n * m
  wrongLaw n m = solveNat
```

The failure prints both normal forms. It treats anything else as an opaque atom
compared by syntax: `minus (n + m) m = n` fails (`minus` is an atom), as do `f (x + y)
= f (y + x)` and every goal that needs a hypothesis (it does not look at `n = m` in
scope). Give it a goal written out in a signature: inline, as `the (S n = n + 1)
solveNat`, it fails because `n + 1` is still unelaborated when the macro runs.

`rewrite p in e` with `p : l = r` replaces `l` by `r` in the goal; "Rewriting by ...
did not change type" (E1001) means `l` does not occur in the goal: check the direction
and whether the goal shows the term the way you think (`:t` on a hole).

"`?altTy` ... is not a rewrite rule type" (E1002) on a rule that plainly is an equation
means its name is ambiguous: your lemma has the name of a library function. One
that you prove yourself under a library's name (`appendNilRightNeutral`, say) clashes
with `Data.List.appendNilRightNeutral` as soon as `Data.List` is imported. Qualify the
name (`rewrite MyModule.appendNilRightNeutral xs in ...`) or rename it.
`:t yourLemma` lists every definition with that name.

**5. Find lemmas instead of guessing names.** Search by type, then check the name:

```sh
printf ':s (n : Nat) -> n + 0 = n\n:browse Data.Nat\n' | idris2 --quiet Proofs.idr
```

`:s` finds `Data.Nat.plusZeroRightNeutral : (left : Nat) -> left + 0 = left`. The
common names (`plusSuccRightSucc`, `plusCommutative`, `plusAssociative`,
`appendNilRightNeutral`, `appendAssociative`, `reverseInvolutive`, `mapFusion`, ...)
are tabled in `references/equality.md`; there are few for `Vect` in base, more in
contrib's `Data.Vect.Properties`.

**6. Check the result.** `:total plusZ` should say `Main.plusZ is total`.

### Index arithmetic in types

`Vect (k + S m) a` versus `Vect (S (k + m)) a` is the same problem: the types are
equal only propositionally, so `rewrite` the goal with a lemma, then give the value.

```idris
snocV : Vect n a -> a -> Vect (S n) a
snocV {n} xs x = rewrite plusCommutative 1 n in xs ++ [x]
```

Here `xs ++ [x] : Vect (n + 1) a` and the goal is `Vect (S n) a`, which is `Vect (1 +
n) a` by evaluation; `plusCommutative 1 n : 1 + n = n + 1` rewrites the goal to
`Vect (n + 1) a`. With `solveNat`, state the equation you need as a local lemma:

```idris
revAcc : Vect k a -> Vect m a -> Vect (k + m) a
revAcc {k} acc [] = rewrite lem in acc
  where 0 lem : k + 0 = k
        lem = solveNat
revAcc {k} {m = S m'} acc (x :: xs) = rewrite lem in revAcc (x :: acc) xs
  where 0 lem : k + S m' = S (k + m')
        lem = solveNat
```

The lemma must be `0` here: `k` and `m'` are erased, and without the `0` the solver's
proof uses them at run time ("k is not accessible in this context"). Often the
cheaper fix is to change the definition so the indices line up by evaluation (recurse
so that the type is built the way `plus` computes).

### Why a proof works in one module and not another

A type can only evaluate a function whose clauses it can see. `export` hides them:
a proof by `Refl` about an `export`ed function fails outside its module with "Can't
solve constraint". Functions used in types, and data whose constructors a proof
matches, must be `public export`. Otherwise use the lemmas the module exports.

## Totality failures

`covering` is the default: missing cases are errors, non-termination is not. `total`
(on a definition, or `%default total`) adds termination and requires everything called
to be total. Read `references/totality.md` for the reasons and complete examples.

| Code | Message | Meaning | Fix |
|---|---|---|---|
| E0601 | `not covering. Missing cases:` | a clause is missing | paste the listed cases; `impossible` if contradictory |
| E0602 | `not covering. Calls non covering function g` | `g` may crash | make `g` covering (return `Maybe`), or the caller `partial` |
| E0602 | `... Integral implementation ... because of ...div, ...mod` | (this fork) `div`/`mod` on a concrete type in a `total` function | `divNatNZ n 2 ItIsSucc`, structural recursion, or `assert_total` when the divisor is a nonzero literal |
| E0602 | `Calls non covering function Data.String.strTail` | primitive string ops are not covering | recurse on `unpack s`, or `strM` + `assert_smaller` |
| E0603 | `is not a valid impossible case` | the case can happen | give it a right hand side |
| E0701 | `not strictly positive` | the type occurs left of an arrow in its own constructor | change the representation |
| E0702/E0703 | `possibly not terminating due to call to g` / `g being reachable via` | something called is not total (the two codes are interchangeable) | fix the function at the end of the path |
| E0704 | `possibly not terminating due to recursive path f`, then `Argument 1: passed e, which is not known to be smaller than the pattern p` | the recursive argument is not a structural subterm | see below |

For E0704, read the "passed ... pattern ..." line, then:

- recursion inside `map`/`foldr`/a lambda: write the list traversal as a local
  function so each call gets a subterm;
- recursion on what a `with` or a function returned (`reverse xs`, `half n`,
  `filter p xs`): a recursive view (`halfRec`, `splitRec`, `snocList`) or well-founded
  recursion with `sizeAccessible` (`references/views-wf.md`);
- arguments rebuilt from parts (`(k, k)`): recurse on the one that shrinks;
- no proof possible or worth it: `Data.Fuel`, or `assert_smaller big small` on the one
  argument, which is honest only if it is true.

`assert_total` turns off all checks for an expression; in a lemma it can prove
anything, so use it only in programs, and say why in a comment.

## Quantities

`(0 x : t)` exists only for the type checker, `(1 x : t)` must be used exactly once,
`(x : t)` is unrestricted. Implicits you do not bind are `0`. Read
`references/quantities.md`.

| Message | Fix |
|---|---|
| `n is not accessible in this context` (E0802) | an erased value used at run time: bind it `{n : _}` / `{n : Nat}`, or compute it from data |
| `Can't match on C (Erased argument)` (E0606) | unrestricted binder, or match a run-time argument that decides it, or mark the definition `0` |
| `There are N uses of linear name x` (E0801) | use it exactly once |
| `Trying to use linear name x in non-linear context` (E0802) | pass it only to `1` arguments (`-@`, `LPair`/`#`, not `(,)`) |

Erased proofs cost nothing: take them as `(0 prf : ...)`, store them as `0` fields
(`Subset`), and a lemma may itself be `0 lemma : ...` and still be used in `rewrite`.

A function whose argument is `1` is accepted where one with an unrestricted argument
is expected (`foldr (::) []` with a linear `(::)`): the compiler eta-expands it, which
is safe because using a value once is one way of using it freely. Only in that
direction, and only when both types are known to be function types at that point:
`List ((1 _ : a) -> b)` is not a `List (a -> b)`. That is all there is of quantity
polymorphism; see `references/quantities.md`.

## References: read this when...

- `references/equality.md`: a proof by `Refl` or `rewrite` fails; you need
  `with ... proof`, `Calc`, `replace`, `Dec`/`DecEq`/`Uninhabited`; you need a lemma
  name; `solveNat`; deriving `Eq`/`Ord`/`DecEq` and what the derivers reject; worked
  proofs (plus commutativity, map fusion, `Vect` reverse with rewrites, a `DecEq`
  implementation by hand).
- `references/totality.md`: any totality or coverage error; `div`/`mod` in `total`
  code; `--method-totality`; `Data.Fuel`; when `assert_total` is honest; positivity;
  `%totality_depth`.
- `references/views-wf.md`: the recursion is right but not structural: views
  (`Parity`, `halfRec`, `splitRec`, `snocList`), `Control.WellFounded` with a total
  quicksort.
- `references/quantities.md`: erased and linear errors, `{n : _}`, matching on erased
  arguments, `Subset`/`Exists`, the `linear` package (`-@`, `LIO`), the cost of
  unerased implicits.
- `cases/`: one file per error code, showing exactly what produces it.
