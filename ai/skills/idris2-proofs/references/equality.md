# Equality proofs

<!-- idris
import Data.Nat
import Data.List
import Data.Vect
import Decidable.Equality
import Syntax.WithProof
import Syntax.PreorderReasoning
import Data.Nat.Solver
import Deriving.Eq
import Deriving.Ord
import Deriving.DecEq

%language ElabReflection
-->

Contents: definitional and propositional equality · the combinators · `rewrite` ·
`with ... proof` and `@@` · equational reasoning with `Calc` · `Dec`, `Uninhabited`,
`void` · deriving `Eq`, `Ord`, `DecEq` · `solveNat` · visibility: why a proof works
in one module and not in another · lemma names · worked proofs (plus commutativity,
map fusion, `Vect` reverse, `DecEq` by hand).

## Definitional and propositional equality

`Refl : x = x` type-checks when both sides *evaluate* to the same term. Evaluation runs
the clauses of a function only when the argument it matches on is a constructor. `plus`
matches on its first argument, so:

```idris
zeroLeft : (n : Nat) -> 0 + n = n
zeroLeft n = Refl                 -- plus Z n reduces to n

failing "Can't solve constraint between: n and plus n 0"
  zeroRight : (n : Nat) -> n + 0 = n
  zeroRight n = Refl              -- plus n Z is stuck: n is a variable
```

When `Refl` fails, the message shows the two stuck terms. The fix is never to try
harder with `Refl`: split on the variable that blocks evaluation (the argument the
function recurses on: the first for `plus`, `++`, `minus`; the list for `map`,
`length`), so that one step reduces, and prove the rest by recursion or by a lemma.
Goals print `+` as `plus` and `map` on lists as `mapImpl`; that is the same function.

## The combinators

From the REPL (`:t`), with quantities shown:

```text
Builtin.sym : (0 _ : x = y) -> y = x
Builtin.trans : (0 _ : a = b) -> (0 _ : b = c) -> a = c
Prelude.cong : (0 f : (t -> u)) -> (0 _ : a = b) -> f a = f b
Prelude.cong2 : (0 f : (t1 -> t2 -> u)) -> (0 _ : a = b) -> (0 _ : c = d) -> f a c = f b d
Builtin.replace : {0 p : _ -> Type} -> (0 _ : x = y) -> (1 _ : p x) -> p y
Prelude.void : (0 _ : Void) -> a
Prelude.absurd : Uninhabited t => t -> a
```

The proofs are erased (quantity 0), so proofs cost nothing at run time, and a function
may take a proof argument as `(0 prf : x = y)`. `replace` usually needs `{p = ...}`
because the motive cannot be guessed:

```idris
castVect : n = m -> Vect n a -> Vect m a
castVect prf xs = replace {p = \k => Vect k a} prf xs
```

## `rewrite`

`rewrite prf in e`, with `prf : l = r`, replaces every `l` in the goal by `r`, then
checks `e` against the new goal. It rewrites the goal, not the types of the variables
in scope, and it goes left to right: when the goal contains `r` and you need `l`, write
`rewrite sym prf in e`.

```idris
plusZeroS : (n : Nat) -> S (n + 0) = S n
plusZeroS n = rewrite plusZeroRightNeutral n in Refl   -- goal S n = S n

failing "Rewriting by n + 0 = n did not change type n = n"
  noMatch : (n : Nat) -> n = n
  noMatch n = rewrite plusZeroRightNeutral n in Refl   -- no n + 0 in the goal

plusZeroS' : (n : Nat) -> S n = S (n + 0)
plusZeroS' n = rewrite plusZeroRightNeutral n in Refl  -- n + 0 on the right: fine too
```

"did not change type" (E1001) means the left side of the equation does not occur in the
goal *as written after evaluation*: check the direction, then check that the goal
shows `plus n 0` and not something that evaluates differently (`:t` on a hole shows the
goal exactly). Several rewrites chain: `rewrite p in rewrite q in e`.

To use an equation on a hypothesis instead of the goal, change the hypothesis's type
with `replace` (above), or `rewrite sym prf` in the goal so that it matches the
hypothesis as it is.

## `with ... proof` and `@@`

A `with` replaces its value by the pattern everywhere in the goal, and then forgets
where the pattern came from. When the value occurs in the goal only under a binder, or
you need the equation as an argument, `with (e) proof p` keeps `p : e = pattern` in
each branch:

```idris
failing "Mismatch between: True and p ?fst"
  firstBad : (p : a -> Bool) -> List a -> Maybe (x : a ** p x = True)
  firstBad p [] = Nothing
  firstBad p (x :: xs) with (p x)
    _ | True = Just (x ** Refl)        -- the goal's p x is under the binder
    _ | False = firstBad p xs

firstTrue : (p : a -> Bool) -> List a -> Maybe (x : a ** p x = True)
firstTrue p [] = Nothing
firstTrue p (x :: xs) with (p x) proof eq
  _ | True = Just (x ** eq)            -- eq : p x = True
  _ | False = firstTrue p xs
```

The same with `Syntax.WithProof`: `@@ e` is `(e ** Refl)` of type `(u ** e = u)`, and
a `case` on it keeps the equation:

```idris
firstTrue' : (p : a -> Bool) -> List a -> Maybe (x : a ** p x = True)
firstTrue' p [] = Nothing
firstTrue' p (x :: xs) = case @@ p x of
  (True ** eq) => Just (x ** eq)
  (False ** _) => firstTrue' p xs
```

## Equational reasoning with `Calc`

`Syntax.PreorderReasoning` writes a chain of steps, each with its justification:

```idris
calcExample : (x : Nat) -> (x + 1) + 0 = 1 + x
calcExample x =
  Calc $
    |~ (x + 1) + 0
    ~~ x + 1         ...(plusZeroRightNeutral (x + 1))
    ~~ 1 + x         ...(plusCommutative x 1)
```

Each `...(prf)` proves "previous line = this line"; `..<(prf)` takes the equation the
other way round. This is the readable form for proofs of four or more steps, and an
error points at the step that is wrong.

## `Dec`, `Uninhabited`, `void`

`Dec p` is `Yes p` or `No (Not p)`, and `Not p` is `p -> Void`. `decEq x y : Dec (x =
y)` exists for every type with a `DecEq` implementation (`Nat`, `List`, `String`, ...).
`Uninhabited t` says `t` has no values; `absurd : Uninhabited t => t -> a`. Write the
implementation with an `impossible` clause, which the compiler checks:

```idris
data Shape = Circle Nat | Square Nat

Uninhabited (Circle n = Square m) where
  uninhabited Refl impossible

Uninhabited (Square n = Circle m) where
  uninhabited Refl impossible
```

## Deriving `Eq`, `Ord` and `DecEq`

`Deriving.Eq`, `Deriving.Ord` and `Deriving.DecEq` (base) write the implementation
with an elaborator script; the file needs `%language ElabReflection`:

```idris
data Tree a = Leaf a | Node (Tree a) a (Tree a)

%hint treeEq : Eq a => Eq (Tree a)
treeEq = %runElab derive

%hint treeOrd : Ord a => Ord (Tree a)
treeOrd = %runElab derive

%hint treeDecEq : DecEq a => DecEq (Tree a)
treeDecEq = %runElab derive

sameTree : Dec (Node (Leaf 1) 2 (Leaf 3) = Node (Leaf 1) 2 (Leaf (the Nat 3)))
sameTree = decEq _ _
```

The result is total (`:total treeDecEq` says so) with no assertions. Write the
implementation as a `%hint` named function, as above: a type that contains itself
under another type (`data Rose = R (List Rose)`) is compared through the
implementation being defined, and without `%hint` the search for `Eq (List Rose)`
fails. What the `DecEq` deriver rejects, with the message it gives:

```idris
data Pos : Type where
  MkPos : (n : Nat) -> (0 ok : IsSucc n) -> Pos

failing "the constructor MkPos has an erased field, whose value cannot be compared"
  posDecEq : DecEq Pos
  posDecEq = %runElab derive

data Ev : Nat -> Type where
  EZ : Ev Z
  ES : Ev n -> Ev (n + 2)

failing "which is not made of constructors and variables"
  evDecEq : DecEq (Ev n)
  evDecEq = %runElab derive
```

`Eq` and `Ord` skip erased fields, so `Eq Pos` derives. An indexed family works when
its constructors' indices are constructors and variables (`Vect (S n) a` style); for
`Ev` write `DecEq` by hand, as in worked proof 4.

## `solveNat`

`Data.Nat.Solver` (contrib, `-p contrib`) has the macro `solveNat`: it proves an
equation of `Nat` that holds in every commutative semiring, over variables, literals,
`S`, `+` and `*`. No induction, no lemma names:

```idris
foil : (x, y, z : Nat) -> (x + y) * (z + 1) = x * z + y + z * y + x
foil x y z = solveNat

failing "the two sides are not equal as polynomials"
  minusLaw : (n, m : Nat) -> minus (n + m) m = n
  minusLaw n m = solveNat

failing "the two sides are not equal as polynomials"
  fromHyp : (n, m : Nat) -> n = m -> n + 1 = m + 1
  fromHyp n m p = solveNat
```

Anything that is not a literal, `S`, `+` or `*` is an atom, compared by syntax:
`minus`, `div`, a function application (`f (x + y)` differs from `f (y + x)`). It
ignores hypotheses (`rewrite p in solveNat` first, then the goal has only `m`). The
failure prints both normal forms, which shows which part is off. Use it on a goal
stated in a signature (a top-level lemma or a `where` lemma); inline, `the (S n = n +
1) solveNat` fails, because `n + 1` is not elaborated yet when the macro looks at it.
A `where` lemma about erased indices must be `0 lem : ...` (see `revAcc'` below).
Literal-only goals need a type: `2 + 3 = 5` alone is about `Integer`, which the
solver refuses ("not an equality of natural numbers"); `Refl` proves it anyway.

## Visibility: a function used in a type must be `public export`

A proof about `double 2` needs `double` to evaluate. `export` gives other modules the
type only; `public export` gives them the clauses too. The same holds for a namespace
in one file, which shows it:

```idris
namespace Hidden
  export
  double : Nat -> Nat
  double n = n + n

namespace Open
  public export
  double' : Nat -> Nat
  double' n = n + n

failing "Can't solve constraint between"
  four : Hidden.double 2 = 4
  four = Refl

four' : Open.double' 2 = 4
four' = Refl
```

So: functions that appear in types (and data types whose constructors a proof
matches on) are `public export`. If a library function is only `export`, use its
lemmas instead of evaluating it. (A literal `4 : Nat` may print as
`S (assert_total (integerToNat 3))` in such messages; it is just 4.)

## Lemma names

Find lemmas by type with `:search` (`:s`), for example `:s (n : Nat) -> n + 0 = n`;
list a module with `:browse Data.Nat`; check a guess with `:t`. Verified here:

| Lemma | Type |
|---|---|
| `plusZeroRightNeutral` | `(left : Nat) -> left + 0 = left` |
| `plusSuccRightSucc` | `(left, right : Nat) -> S (left + right) = left + S right` |
| `plusCommutative` | `(left, right : Nat) -> left + right = right + left` |
| `plusAssociative` | `(left, centre, right : Nat) -> left + (centre + right) = left + centre + right` |
| `plusLeftCancel` | `(left, right, right' : Nat) -> left + right = left + right' -> right = right'` |
| `multCommutative` | `(left, right : Nat) -> left * right = right * left` |
| `minusPlus` | `(m : Nat) -> minus (plus m n) m = n` |
| `lteSuccRight` | `LTE n m -> LTE n (S m)` |
| `reverseInvolutive` | `(xs : List a) -> reverse (reverse xs) = xs` |
| `appendNilRightNeutral` | `(l : List a) -> l ++ [] = l` |
| `appendAssociative` | `(l, c, r : List a) -> l ++ (c ++ r) = (l ++ c) ++ r` |
| `revAppend` | `(vs, ns : List a) -> reverse ns ++ reverse vs = reverse (vs ++ ns)` |
| `mapFusion` | `(g : b -> c) -> (f : a -> b) -> (xs : List a) -> map g (map f xs) = map (g . f) xs` |
| `mapAppend` | `(f : a -> b) -> (xs, ys : List a) -> map f (xs ++ ys) = map f xs ++ map f ys` |
| `lengthMap` | `(xs : List a) -> length (map f xs) = length xs` |

The first eight are in `Data.Nat`, the rest in `Data.List` (base). Other names are in
`contrib` (`-p contrib`): `Data.List.Equalities.lengthDistributesOverAppend`
(`length (xs ++ ys) = length xs + length ys`), and `Data.Vect.Properties` (`mapFusion`,
`mapId`, `vectorExtensionality` on `Vect`). `Data.Vect` itself has almost no lemmas.
Several modules use the same name (`appendAssociative` exists for `List`, `List1` and
`SnocList`): qualify it if the type does not pick one.

## Worked proofs

### 1. Plus commutativity by hand

State it, leave holes, read the goals (`:t base`, `:t step`):

```text
base : m = plus m 0
step : S (plus k m) = plus m (S k)
```

Both goals are stuck on `m` in the first position of `plus`, so they need lemmas that
recurse on `m`:

```idris
plusZ : (m : Nat) -> m = m + 0
plusZ Z = Refl
plusZ (S k) = cong S (plusZ k)

plusS : (m, k : Nat) -> S (m + k) = m + S k
plusS Z k = Refl
plusS (S j) k = cong S (plusS j k)

myPlusComm : (n, m : Nat) -> n + m = m + n
myPlusComm Z m = plusZ m
myPlusComm (S k) m = rewrite myPlusComm k m in plusS m k
```

In `step`, `rewrite myPlusComm k m` turns `S (plus k m)` into `S (plus m k)`, and `plusS
m k` is exactly the rest.

### 2. Map fusion on lists

```idris
mapFuse : (f : b -> c) -> (g : a -> b) -> (xs : List a) ->
          map f (map g xs) = map (f . g) xs
mapFuse f g [] = Refl
mapFuse f g (x :: xs) = cong (f (g x) ::) (mapFuse f g xs)
```

After the split on `xs` the goal is `f (g x) :: mapImpl f (mapImpl g xs) = f (g x) ::
mapImpl (\x => f (g x)) xs`: the heads agree by evaluation, the tails by recursion, and
`cong` puts the head back. `rewrite mapFuse f g xs in Refl` works too.

### 3. `Vect` reverse with an accumulator

The index arithmetic does not line up by evaluation: the recursive call has length
`S k + m` and the goal wants `k + S m`.

```idris
revAcc : Vect k a -> Vect m a -> Vect (k + m) a
revAcc {k} acc [] = rewrite plusZeroRightNeutral k in acc
revAcc {k} {m = S m'} acc (x :: xs) =
  rewrite sym (plusSuccRightSucc k m') in revAcc (x :: acc) xs

vreverse : Vect n a -> Vect n a
vreverse xs = revAcc [] xs                -- 0 + n evaluates to n
```

`k` and `m` are bound with `{k}` and `{m = S m'}` so they can be named. They stay
erased, which is fine because they only appear in the proofs. With `solveNat`, each
clause states the equation it needs instead of finding `plusSuccRightSucc`:

```idris
revAcc' : Vect k a -> Vect m a -> Vect (k + m) a
revAcc' {k} acc [] = rewrite lem in acc
  where 0 lem : k + 0 = k
        lem = solveNat
revAcc' {k} {m = S m'} acc (x :: xs) = rewrite lem in revAcc' (x :: acc) xs
  where 0 lem : k + S m' = S (k + m')
        lem = solveNat
```

 `sym` is needed because the goal contains `k + S m'` and the
lemma's left side is `S (k + m')`.

### 4. A `DecEq` implementation

This is what `derive` writes for you (above); by hand is the fallback for a type the
deriver rejects, or an older compiler without `Deriving.DecEq`. Equal constructors
decide their arguments, different constructors are refuted by the `Uninhabited` implementations
above.

```idris
circleInj : Circle n = Circle m -> n = m
circleInj Refl = Refl

squareInj : Square n = Square m -> n = m
squareInj Refl = Refl

DecEq Shape where
  decEq (Circle n) (Circle m) = case decEq n m of
    Yes prf => Yes (cong Circle prf)
    No contra => No (contra . circleInj)
  decEq (Square n) (Square m) = case decEq n m of
    Yes prf => Yes (cong Square prf)
    No contra => No (contra . squareInj)
  decEq (Circle _) (Square _) = No absurd
  decEq (Square _) (Circle _) = No absurd
```

`No` needs a function from the equation to `Void`; the injectivity lemma turns `Circle
n = Circle m` into `n = m`, which `contra` refutes.
