# Quantities: erased (0), linear (1), unrestricted

<!-- idris
import Data.Vect
import Data.Nat
import Data.DPair
import Control.Linear.LIO
import Data.Linear.Notation
-->

Contents: what the three mean · implicit arguments are erased · what an erased value
may be used for · matching on erased arguments · erased proofs in data · linear names ·
linear functions where unrestricted ones are expected · the `linear` package · what
keeping an implicit costs · codes.

## What the three mean

Every binder has a quantity: how often the body may use the value *at run time*.

| Written | Quantity | The body may |
|---|---|---|
| `(0 x : t)` | erased | use `x` only in types and in other erased positions; it does not exist at run time |
| `(1 x : t)` | linear | use `x` exactly once at run time |
| `(x : t)` | unrestricted | use `x` any number of times |

Uses inside types never count, so an erased index can still appear in the result type.
There is no quantity polymorphism here: a function is written once per quantity it
needs. The one bridge is the eta-expansion in "Linear functions where unrestricted
ones are expected" below.

## Implicit arguments are erased

A lower-case name in a signature that is not bound anywhere (`n` in `Vect n a`) is
bound for you as `{0 n : _}`. So it is there for type checking, and gone at run time:

```idris
failing "n is not accessible in this context"
  len : Vect n a -> Nat
  len _ = n

len : {n : _} -> Vect n a -> Nat     -- or {n : Nat} ->
len _ = n
```

`{n : _}` (or `{n : Nat}`) is an unrestricted implicit: the caller still does not write
it, but it is passed at run time. The alternative is to compute what you need from a
value that does exist (`length xs`, or match the `Vect`).

## What an erased value may be used for

```idris
idE : (0 n : Nat) -> Vect n a -> Vect n a   -- in types: yes
idE n xs = xs

vlen : (0 n : Nat) -> Vect n a -> Nat       -- matched, when another argument decides it
vlen Z [] = 0
vlen (S k) (_ :: xs) = S (vlen k xs)

0 isZero : (0 n : Nat) -> Bool             -- anything, inside a 0 definition
isZero Z = True
isZero (S _) = False

failing "n is not accessible in this context"
  sizeOf : (0 n : Nat) -> Nat
  sizeOf n = n                              -- returned at run time: no
```

A definition marked `0` exists only in types and proofs, so it may use its arguments
freely; it cannot be called from run-time code. Passing an erased value to an
unrestricted argument is a run-time use, and fails the same way.

## Matching on erased arguments

A match on an erased argument has to be decided without looking at it. That is fine
when only one constructor fits the type, or when another (run-time) argument decides it
(`vlen` above: the `Vect` decides `n`). Otherwise it is E0606:

```idris
failing "Can't match on 0 (Erased argument)"
  isZ : (0 n : Nat) -> Bool
  isZ Z = True
  isZ (S _) = False

failing "Can't match on LTEZero (Erased argument)"
  lteSize : (0 p : LTE n m) -> Nat
  lteSize LTEZero = 0
  lteSize (LTESucc q) = 1

eqUse : (0 _ : x = y) -> Nat              -- one constructor: fine
eqUse Refl = 0
```

The variables such a match binds are erased too: `predLTE : (0 _ : LTE (S n) (S m)) ->
LTE n m` with `predLTE (LTESucc p) = p` fails with "p is not accessible", and works
when marked `0 predLTE`, or when the result is used only in erased positions.

Fixes for E0606: make the argument unrestricted if the function really branches on
it; or branch on a run-time value that determines it; or make the definition `0`.

## Erased proofs in data

A proof that is only there for the type checker belongs in an erased field. The
library types (`Data.DPair`):

```text
Data.DPair.Subset.Element : (fst : type) -> (0 _ : pred fst) -> Subset type pred
Data.DPair.Exists.Evidence : (0 fst : type) -> this fst -> Exists this
```

`Subset` keeps the value and erases the proof; `Exists` erases the witness and keeps
the value. A dependent pair `(n : Nat ** Vect n a)` keeps both.

```idris
small : (xs : List Nat) -> Maybe (Subset (List Nat) (\ys => LTE (length ys) 3))
small xs = case isLTE (length xs) 3 of
  Yes prf => Just (Element xs prf)
  No _ => Nothing

someVect : Exists (\n => Vect n Nat)
someVect = Evidence 2 [1, 2]

sumSome : Exists (\n => Vect n Nat) -> Nat
sumSome (Evidence _ v) = sum v
```

In your own records, write `0 ok : prf` for such a field; `auto 0` (`{auto 0 ok : LTE n
m}`) makes the caller's proof search fill it.

## Linear names

A linear value must be consumed exactly once: neither dropped nor copied. That makes it
a resource (a handle, a protocol state) whose old versions cannot be used again.

```idris
failing "There are 0 uses of linear name x"
  drop1 : (1 x : a) -> ()
  drop1 x = ()

failing "There are 2 uses of linear name x"
  twice : (1 x : a) -> (1 g : (1 _ : a) -> (1 _ : a) -> b) -> b
  twice x g = g x x

failing "Trying to use linear name x in non-linear context"
  dup : (1 x : a) -> (a, a)
  dup x = (x, x)
```

Wrong use count is E0801. Passing a linear name to an argument that is not linear
(here the fields of `(,)`, which are unrestricted) is E0802, even when it is used only
once: the receiver could copy it. Use `LPair` (`x # y`, linear fields) instead of a
tuple, and a function whose argument is `1` (`(1 _ : a) -> b`, or `a -@ b`) where a
linear value is passed on.

## Linear functions where unrestricted ones are expected

A function that uses its argument once may be passed where a function with an
unrestricted argument is expected: the caller may hand it any value, and using it
once is allowed. The compiler eta-expands it (`(::)` becomes `\x, xs => x :: xs`):

```idris
data LList : Type -> Type where
  LNil  : LList a
  LCons : (1 x : a) -> (1 xs : LList a) -> LList a

fromList : List a -> LList a
fromList = foldr LCons LNil

lid : (1 x : Nat) -> Nat
lid x = x

useU : (Nat -> Nat) -> Nat
useU f = f 1

viaLinear : Nat
viaLinear = useU lid
```

It is not quantity polymorphism. It works only from `1` to unrestricted (an
unrestricted function may copy its argument, so it is no linear function), never for
`0`, and only where both types are already known to be function types; it does not go
inside other types:

```idris
useL : ((1 _ : Nat) -> Nat) -> Nat
useL f = f 1

uid : Nat -> Nat
uid x = x

failing "Mismatch between: Nat -> Nat and (1 _ : Nat) -> Nat"
  wrongWay : Nat
  wrongWay = useL uid

linears : List ((1 _ : Nat) -> Nat)
linears = [lid]

failing "Mismatch between: (1 _ : Nat) -> Nat and Nat -> Nat"
  inList : List (Nat -> Nat)
  inList = linears
```

Older compilers reject `useU lid` too.

## The `linear` package

`-p linear` (or `depends = linear`). `Data.Linear.Notation` has `a -@ b` for `(1 _ : a)
-> b` and `!* a` for an unrestricted value inside a linear context. `Control.Linear.LIO`
has `L io a` (an IO action whose result is unrestricted), `L1 io a` (whose result is
linear and must be used), `pure1`, and `run : L io a -@ io a`.

A resource is handed to a continuation, and each operation consumes the old state and
returns a new one, so the type checker sees a single thread of use:

```idris
data Counter : Type where
  MkCounter : Nat -> Counter

newCounter : LinearIO io => (1 k : (1 _ : Counter) -> L io a) -> L io a
newCounter k = k (MkCounter 0)

tick : LinearIO io => (1 _ : Counter) -> L1 io Counter
tick (MkCounter n) = pure1 (MkCounter (S n))

done : LinearIO io => (1 _ : Counter) -> L io Nat
done (MkCounter n) = pure n

countTwo : LinearIO io => L io Nat
countTwo = newCounter $ \c => do
  c <- tick c
  c <- tick c
  done c

swapL : LPair a b -@ LPair b a
swapL (x # y) = y # x
```

`run countTwo` in `main` prints 2. Writing `c1 <- tick c; c2 <- tick c` fails with
"There are 0 uses of linear name c1", and a continuation that never calls `done`
fails with "There are 0 uses of linear name c": both mistakes are caught.

## What keeping an implicit costs

An erased implicit costs nothing. An unrestricted one (`{n : Nat}`) is a real argument:
every call, recursive ones included, passes it, and every caller must have it at run
time, so `{n : Nat}` spreads to the callers' signatures. Keep an index only where the
code reads it, and prefer recomputing a length from the data when that is cheap.
Mark proof arguments `0` (`(0 prf : LTE n m)`), so they are not built at run time.

## Codes

| Code | Message | Fix |
|---|---|---|
| E0606 | `Can't match on C (Erased argument)` | unrestricted binder, decide from another argument, or a `0` definition |
| E0802 | `x is not accessible in this context` | the erased `x` is used at run time: bind it as `{x : _}` / `(x : t)` |
| E0802 | `Trying to use linear name x in non-linear context` | pass it to a linear argument (`-@`, `LPair`) |
| E0801 | `There are N uses of linear name x` | use it exactly once |

Each code is pinned by a file in `../cases/`.
