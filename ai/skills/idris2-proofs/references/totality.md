# Totality: what is checked, and how to get a function accepted

<!-- idris
import Data.Nat
import Data.String
import Data.Fuel
-->

Contents: the three levels · how termination is decided · false negatives and their
fixes · method totality (this fork) · `Data.Fuel` · `assert_total` and
`assert_smaller` · coverage and `impossible` · positivity · `%totality_depth` · codes.

## The three levels

| Annotation | Checked | Typical use |
|---|---|---|
| `partial` | nothing | a REPL loop, a server, a search that may diverge |
| `covering` | every input has a clause; every function called is covering | ordinary programs: **the default** |
| `total` | covering, and every recursion terminates, and every function called is total | proofs, functions used in types |

Because `covering` is the default, a missing clause is an error even without an
annotation, but a loop is not:

```idris
loop : Nat -> Nat
loop n = loop n            -- accepted: covering does not look at termination

failing "Missing cases"
  headM : List a -> a
  headM (x :: _) = x
```

`%default total` at the top of a file, or `--total` on the command line, raises the
default; `partial` or `covering` on a definition lowers it again. A proof that is not
total proves nothing (`loop` above "proves" any type), which is why a lemma should be
`total`, and why a `total` function may only call total functions:

```idris
failing "possibly not terminating due to call to Main.loop"
  total
  useLoop : Nat -> Nat
  useLoop n = loop n
```

Ask the compiler what it concluded with `:total NAME` (REPL), for example
`Main.loop is possibly not terminating due to recursive path Main.loop`.

## How termination is decided

Idris uses size-change termination: for every recursive call (also round a cycle of
mutually recursive functions) it compares each argument with the pattern on the left
hand side. An argument counts as smaller when it is a variable bound *inside* a
constructor pattern of that argument (`k` in `S k`, `xs` in `x :: xs`, also deeper:
`Just xs` against `Just (x :: xs)`). Some argument must get smaller on every path
through the cycle; which one may differ per call, so `ack` below is accepted. Tuples are
looked into as well.

```idris
total
ack : Nat -> Nat -> Nat
ack Z n = S n
ack (S m) Z = ack m 1
ack (S m) (S n) = ack m (ack (S m) n)

total
pairs : (Nat, Nat) -> Nat
pairs (Z, _) = 0
pairs (S k, m) = pairs (k, m)
```

What the checker does *not* know: that a function returns something smaller (`minus`,
`div`, `filter`, `drop`, `strTail`), anything about primitive types (`String`, `Int`,
`Integer`, `Bits64`), and the size of an argument that it only sees under a function
that is not applied to all its arguments.

## False negatives and their fixes

Each of these is a correct function the checker rejects; the message names the call
and the argument (`not known to be smaller than the pattern ...`).

**Recursion through `map` / `foldr`.** In `map size ts` the recursive `size` is not
applied, so nothing is compared; in `map (\t => size t) ts` the lambda's `t` is not a
subterm of the pattern.

```idris
data Rose a = Node a (List (Rose a))

failing "not known to be smaller than the pattern Node _ ts"
  total
  size : Rose a -> Nat
  size (Node _ ts) = S (sum (map (\t => size t) ts))
```

Fix: write the traversal of the list yourself, as a local function (or a `mutual`
block); then every call is applied to a structural subterm.

```idris
total
size : Rose a -> Nat
size (Node _ ts) = S (sizes ts)
  where
    sizes : List (Rose a) -> Nat
    sizes [] = 0
    sizes (t :: rest) = size t + sizes rest
```

**Recursion on what a `with` returned.** `with (reverse xs)` gives you `y :: ys`, but
`ys` is a subterm of `reverse xs`, not of `xs`:

```idris
failing "possibly not terminating due to recursive path Main.lastRev"
  total
  lastRev : List Nat -> Nat
  lastRev xs with (reverse xs)
    lastRev xs | [] = 0
    lastRev xs | (y :: ys) = lastRev ys
```

Fix: use a *view* whose constructors carry the recursive structure (`snocList`,
`splitRec`, `halfRec`), and recurse with `f xs | rec` on the view's own subterm; or
well-founded recursion. Both are in `views-wf.md`. (A `with` on a value that is not
recursed into, such as `with (x == 0)`, is no problem.)

**Arguments that are rebuilt, not taken apart.** `(k, k)` against `(S k, Z)` is not
smaller: the second component grew.

```idris
failing "passed (k, k), which is not known to be smaller than the pattern (S k, 0)"
  total
  g : (Nat, Nat) -> Nat
  g (Z, _) = 0
  g (S k, S j) = g (k, j)
  g (S k, Z) = g (k, k)
```

Fix: recurse on one argument only (here `g` really decreases on the first component:
make it a separate argument, `g : Nat -> Nat -> Nat`, and the call `g k k` is accepted
because the first argument is a subterm), or use `Data.Fuel`.

**Functions that shrink their argument.** `loopy (S k) = loopy (minus (S k) 1)` is
rejected (`passed minus (S k) 1`). Match deeper instead of computing (`loopy (S k) =
loopy k`), or use well-founded recursion with a proof that the result is `LT`.

**Strings.** A `String` is primitive, so `strM` and `unpack` give views, not
subterms. `strTail` is not even covering (it wraps a primitive): a `total` function
that calls it fails with E0602, `Calls non covering function Data.String.strTail`.

```idris
failing "No argument gets smaller"
  total
  chars : String -> Nat
  chars s = case strM s of
    StrNil => 0
    StrCons c rest => S (chars rest)

total
chars : String -> Nat
chars s = go (unpack s)          -- recurse on a List Char instead
  where
    go : List Char -> Nat
    go [] = 0
    go (_ :: cs) = S (go cs)

total
chars' : String -> Nat
chars' s = case strM s of        -- or say why it terminates
  StrNil => 0
  StrCons c rest => S (chars' (assert_smaller s rest))
```

## Method totality (this fork)

A total function is only as total as the methods it calls. `div` and `mod` of
`Integral` are declared `partial` (division by zero), so on this compiler a `total`
function that uses them on a concrete type fails, although upstream 0.8 accepts it:

```idris
failing "because of Data.Nat.div, Data.Nat.mod"
  total
  half : Nat -> Nat
  half n = n `div` 2
```

The full message is E0602: `half is not covering ... Calls non covering function
Data.Nat.Integral implementation at Data.Nat:...`. For `Int` or `Integer` it names
`Prelude.Num.div, Prelude.Num.mod`. Fixes, best first:

```idris
total
half1 : Nat -> Nat
half1 n = divNatNZ n 2 ItIsSucc        -- a proof that 2 is not zero (erased)

total
half2 : Nat -> Nat                     -- or compute it structurally
half2 (S (S k)) = S (half2 k)
half2 _ = 0

total
half3 : Int -> Int
half3 x = assert_total $ x `div` 2     -- honest: 2 is not zero

total
plusOnly : Int -> Int
plusOnly x = x + 2                     -- other methods are fine
```

`divNatNZ`, `modNatNZ` and `divmodNatNZ` (`Data.Nat`) take `(0 _ : NonZero y)`; pass
`ItIsSucc` for a literal or an `S _`. When your own function asks its caller for such
a proof (`{auto 0 ok : NonZero d}`), the search runs in the caller's module, which
then needs `Data.Nat` in scope: without it a call like `half 10 2` fails with "Can't
find an implementation for NonZero 2". Write `import public Data.Nat` in the module
that declares the function, so that importing it is enough. The check is per method: only an implementation
whose used methods are not covering is blamed. A function generic in the
implementation (`Integral a => a -> a`) is total, and the blame moves to the caller that
picks `Int`.

Only `total` functions are checked this way. With `--method-totality`, `covering`
functions are too (so `half` without `total` fails as well). Without the flag, a
`covering` function ``halfL n = n `div` 2`` in a library is accepted, but a `total`
function in another module that calls it is not: `Calls non covering function
Lib2.halfL` / `Lib2.halfL is not covering, because of Data.Nat.Integral
implementation`. The blame travels through the TTC files.

## `Data.Fuel`: when termination is not provable

`data Fuel = Dry | More (Lazy Fuel)`. Recursing on fuel is structural, so the function
is total; the caller decides how much: `limit n` gives `n` steps, `forever` never runs
out but is itself only `covering`.

```idris
total
collatz : Fuel -> Nat -> Maybe Nat        -- steps to reach 1, if fuel lasts
collatz Dry _ = Nothing
collatz (More f) n =
  if n <= 1 then Just 0
  else map S (collatz f (if mod2 n then 3 * n + 1 else half2 n))
  where
    mod2 : Nat -> Bool
    mod2 Z = False
    mod2 (S Z) = True
    mod2 (S (S k)) = mod2 k
```

## `assert_total` and `assert_smaller`

- `assert_smaller big small` tells the checker that `small` is smaller than `big`
  (the pattern it is compared with). Use it on the recursive call's argument.
- `assert_total e` stops checking `e` altogether, coverage included.

They are honest when you could write the proof but it would cost more than it is
worth: a string that loses a character, a division by a nonzero literal, a list that a
`filter` made no longer. They are lies when the claim is false, and a lie in a proof is
a proof of anything: never use them in a lemma whose statement you are not sure of.
Prefer `assert_smaller` (one call) over `assert_total` (a whole expression).

## Coverage and `impossible`

A clause written with `impossible` instead of a right hand side tells Idris a case
cannot occur, and the compiler checks the claim: the patterns must fail to type-check
because of a contradiction in the constructors.

```idris
zeroNotSucc : (n : Nat) -> Z = S n -> Void
zeroNotSucc _ Refl impossible

failing "f 0 is not a valid impossible case"
  f : Nat -> Nat
  f Z impossible
  f (S k) = k
```

Coverage takes the types of the arguments into account, so with indexed types you
usually do not need the impossible clause at all: `vhead : Vect (S n) a -> a` with one
clause for `x :: _` is covering. Write the `impossible` clause when Idris reports the
case as missing although it cannot happen; it then shows the contradiction itself. The
missing cases in an E0601 message are valid patterns to paste.

## Positivity

A data type that mentions itself to the left of an arrow in a constructor argument lets
you write a non-terminating term without recursion, so it is not total. Under the
default (`covering`) the declaration is accepted; the error comes where totality is
required: on the type itself when it is declared `total` (or under `%default total`),
and on any `total` function that uses its constructors.

```idris
failing "Bad is not total, not strictly positive"
  total
  data Bad = MkBad (Bad -> Nat)

data Bad = MkBad (Bad -> Nat)

failing "Main.MkBad is not total, not strictly positive"
  total
  selfApp : Bad -> Nat
  selfApp (MkBad g) = g (MkBad g)
```

A type that only occurs to the right of arrows (`Node a (List (Rose a))`, `MkT (Nat ->
T)`) is fine.

## `%totality_depth`

How many constructors deep the checker looks when comparing an argument with its
pattern (default 5). `h (Just (Just (Just (x :: y :: xs)))) = h (Just (Just (Just
xs)))` is accepted by default and rejected with `%totality_depth 2`. Raise it only when a
message shows a deeply nested pattern that really is smaller; it slows the check.

## Codes

| Code | Message starts | Usual fix |
|---|---|---|
| E0601 | `f is not covering. Missing cases:` | paste the cases; `impossible` for contradictions |
| E0602 | `f is not covering. Calls non covering function g` | make `g` covering; this fork: `divNatNZ`/`assert_total` for `div`/`mod` |
| E0603 | `... is not a valid impossible case` | the case is possible: give a right hand side |
| E0701 | `T is not total, not strictly positive` | change the representation |
| E0702, E0703 | `f is not total, possibly not terminating due to call to g` or `... due to function g being reachable via ...` | make `g` (the end of the path shown) total, or lower `f` to `covering` |
| E0704 | `... due to recursive path f` | structural subterm, view, well-founded recursion, fuel, `assert_smaller` |

E0702 and E0703 mean the same thing; which one you get depends on the order in which
the compiler checked the functions (the first `total` caller of a looping function
gets E0703, the next one E0702), so do not branch on the difference. Each code is
pinned by a file in `../cases/`.
