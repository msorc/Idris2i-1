# Views and well-founded recursion

<!-- idris
import Data.Nat
import Data.List
import Data.Nat.Views
import Data.List.Views
import Control.WellFounded
-->

Read this when a function is correct but the totality checker rejects its recursion:
the recursive argument is computed (half of `n`, the first half of a list, the result of
`filter`) instead of being a variable bound in a pattern.

Contents: `with` and views · writing a view · recursive views from the library
(`halfRec`, `splitRec`, `snocList`) · well-founded recursion (`sizeAccessible`,
`sizeRec`, `wfInd`) · which to choose.

## `with` and views

`f x with (e)` matches on the value of `e` as if it were another argument. When the
type of `e` mentions `x`, the match also tells you what `x` is, and the patterns left
of the `|` are refined accordingly (they may then contain functions such as `j + j`,
because the view, not a match, determined them). Write `_` left of the `|` when you do
not need the refined form.

A *view* is a data type indexed by the value it describes, together with a *covering
function* that builds it for every value:

```idris
data Parity : Nat -> Type where
  Even : {n : Nat} -> Parity (n + n)
  Odd  : {n : Nat} -> Parity (S (n + n))

parity : (n : Nat) -> Parity n
parity Z = Even {n = Z}
parity (S Z) = Odd {n = Z}
parity (S (S k)) with (parity k)
  parity (S (S (j + j))) | Even
    = rewrite plusSuccRightSucc j j in Even {n = S j}
  parity (S (S (S (j + j)))) | Odd
    = rewrite plusSuccRightSucc j j in Odd {n = S j}
```

`{n : Nat}` (not just `{n}`) keeps `n` at run time, because the function using the view
reads it; see `quantities.md`.

A plain view does not help termination by itself: recursing on `j` after matching `k`
as `j + j` is rejected, because `j` is not a subterm of `k`.

```idris
failing "possibly not terminating due to recursive path Main.natToBin"
  total
  natToBin : Nat -> List Bool
  natToBin Z = []
  natToBin k with (parity k)
    natToBin (j + j) | Even = False :: natToBin j
    natToBin (S (j + j)) | Odd = True :: natToBin j
```

## Recursive views

A *recursive* view carries the view of the smaller value inside its constructor, so you
recurse on the view: `f j | rec` means "call `f j` and use `rec` as the result of its
`with`", and `rec` is a structural subterm of what you matched. `Data.Nat.Views`:

```text
data HalfRec : Nat -> Type where
  HalfRecZ : HalfRec Z
  HalfRecEven : (n : Nat) -> (rec : Lazy (HalfRec n)) -> HalfRec (n + n)
  HalfRecOdd : (n : Nat) -> (rec : Lazy (HalfRec n)) -> HalfRec (S (n + n))
halfRec : (n : Nat) -> HalfRec n
```

```idris
total
natToBin : Nat -> List Bool
natToBin k with (halfRec k)
  natToBin Z | HalfRecZ = []
  natToBin (j + j) | HalfRecEven j rec = False :: natToBin j | rec
  natToBin (S (j + j)) | HalfRecOdd j rec = True :: natToBin j | rec
```

`Data.List.Views` has `splitRec` (halves, for divide and conquer) and `snocList` (the
list seen from its end):

```text
SplitRecNil : SplitRec []
SplitRecOne : (x : a) -> SplitRec [x]
SplitRecPair : (lefts, rights : List a) -> (lrec : Lazy (SplitRec lefts)) ->
               (rrec : Lazy (SplitRec rights)) -> SplitRec (lefts ++ rights)
Empty : SnocList []
Snoc : (x : a) -> (xs : List a) -> (rec : SnocList xs) -> SnocList (xs ++ [x])
```

```idris
total
mergeSort : Ord a => List a -> List a
mergeSort xs with (splitRec xs)
  mergeSort [] | SplitRecNil = []
  mergeSort [x] | SplitRecOne x = [x]
  mergeSort (lefts ++ rights) | SplitRecPair lefts rights lrec rrec
    = merge (mergeSort lefts | lrec) (mergeSort rights | rrec)

total
dropLast : List a -> List a
dropLast xs with (snocList xs)
  dropLast [] | Empty = []
  dropLast (ys ++ [y]) | Snoc y ys rec = ys

total
isPalindrome : Eq a => List a -> Bool
isPalindrome xs with (snocList xs)
  isPalindrome [] | Empty = True
  isPalindrome (ys ++ [y]) | Snoc y ys rec = case ys of
    [] => True
    (z :: zs) => z == y && isPalindrome (assert_smaller (ys ++ [y]) zs)
```

`isPalindrome` needs `assert_smaller`: after the first and last element are removed,
`zs` has no view of its own. The honest alternative is the well-founded version below,
or contrib's `Data.List.Palindrome`. A view is an ordinary value built at run time
(`splitRec` in O(n log n), `snocList` in linear time, as their documentation says).

## Well-founded recursion

When no view fits, recurse on a proof that the argument got smaller. `Control.WellFounded`:

```text
data Accessible : (rel : a -> a -> Type) -> (x : a) -> Type where
  Access : (rec : (y : a) -> rel y x -> Accessible rel y) -> Accessible rel x
interface Sized a where size : a -> Nat     -- Nat, List a, pairs
Smaller x y = size x `LT` size y
sizeAccessible : Sized a => (x : a) -> SizeAccessible x
sizeRec : Sized a => (step : (x : a) -> ((y : a) -> Smaller y x -> b) -> b) -> (z : a) -> b
sizeInd, wfRec, wfInd, accRec, accInd: the same with a dependent result or another relation
```

The recursion is structural on the `Accessible` proof: `Access rec` is matched, and
`rec y prf` is a subterm. The proof is erased (`0 acc`), so at run time this is plain
recursion. Quicksort recurses on `filter`, whose result is not a subterm; a lemma says
it is no longer:

```idris
filterLen : (p : a -> Bool) -> (xs : List a) ->
            LTE (length (filter p xs)) (length xs)
filterLen p [] = LTEZero
filterLen p (x :: xs) with (p x)
  _ | True = LTESucc (filterLen p xs)
  _ | False = lteSuccRight (filterLen p xs)

qsort : Ord a => (xs : List a) -> (0 acc : SizeAccessible xs) -> List a
qsort [] _ = []
qsort (x :: xs) (Access rec)
  = qsort (filter (< x) xs) (rec _ (LTESucc (filterLen _ xs)))
    ++ x :: qsort (filter (>= x) xs) (rec _ (LTESucc (filterLen _ xs)))

total
quicksort : Ord a => List a -> List a
quicksort xs = qsort xs (sizeAccessible xs)
```

`Smaller ys (x :: xs)` is `LTE (S (length ys)) (S (length xs))`, so the proof is
`LTESucc` of "`ys` is not longer than `xs`". The same with `sizeRec`, which hides the
`Accessible` argument:

```idris
total
quicksort' : Ord a => List a -> List a
quicksort' = sizeRec step
  where
    step : (xs : List a) -> ((ys : List a) -> Smaller ys xs -> List a) -> List a
    step [] _ = []
    step (x :: xs) rec = rec (filter (< x) xs) (LTESucc (filterLen _ xs))
                         ++ x :: rec (filter (>= x) xs) (LTESucc (filterLen _ xs))
```

For a measure other than `length`, give a `Sized` implementation, or use `wfRec`/`wfInd`
with any relation that has a `WellFounded` implementation (`WellFounded Nat LT` is in
the library).

## Which to choose

| Situation | Use |
|---|---|
| recursion on a subterm the checker does not see (through `map`, a tuple rebuilt) | restructure: local helper, separate argument |
| halving a `Nat`, divide and conquer on lists, working from the end of a list | `halfRec`, `splitRec`, `snocList` |
| any measure that decreases, with a short proof | `sizeAccessible` / `sizeRec` |
| no proof in sight, the function is a program, not a lemma | `Data.Fuel`, or `assert_smaller` with a comment saying why |
