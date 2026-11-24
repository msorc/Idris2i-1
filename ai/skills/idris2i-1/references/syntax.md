# Idris2i-1 syntax by example

Every `idris` block in this file is type-checked by the compiler, so each form can be
copied. The file is one module; its imports are in the comment block below.

<!-- idris
import Data.List
import Data.Maybe
import Data.String
import Data.Vect
import Deriving.Eq
import Deriving.Ord
import Deriving.Show
-->

Contents: [files and modules](#files-and-modules) · [functions](#functions) ·
[data types](#data-types) · [records](#records) · [interfaces](#interfaces) ·
[implicit arguments](#implicit-arguments) · [`do` and effects](#do-and-effects) ·
[strings](#strings) · [numbers](#numbers) · [collections](#collections) ·
[operators](#operators) · [visibility, totality, namespaces](#visibility-totality-namespaces) ·
[dependent types](#dependent-types) · [laziness](#laziness) · [pragmas](#pragmas)

## Files and modules

A file starts with an optional module header, then all imports, then declarations.
Module `Data.Queue` must be the file `Data/Queue.idr` under the source directory; a
file without a header is module `Main`.

```text
module Data.Queue

import Data.List                -- names usable unqualified
import Data.SortedMap as M      -- also usable as M.lookup
import public Data.Vect         -- re-exported to whoever imports this module

%default total                  -- every definition below must be total
```

Comments are `-- line` and `{- block -}`. A documentation comment is `|||` on the lines
before a declaration; `:doc name` shows it.

## Functions

A top-level definition needs a type signature, with a single colon. Lambdas and `case`
alternatives use `=>`.

```idris
||| Doubles a number.
double : Int -> Int
double x = x * 2

applyTwice : (a -> a) -> a -> a
applyTwice f = f . f

classify : Int -> String
classify n =
  if n < 0 then "negative"
  else case n of
         0 => "zero"
         1 => "one"
         _ => "many"

area : Double -> Double -> Double
area w h =
  let scale : Double
      scale = 2.0
      base = w * h              -- a simple local value needs no signature
  in scale * base

sumSquares : List Int -> Int
sumSquares xs = go 0 xs
  where
    go : Int -> List Int -> Int -- a local function needs its signature
    go acc [] = acc
    go acc (y :: ys) = go (acc + y * y) ys

incAll : List Int -> List Int
incAll = map (\x => x + 1)      -- also: map (+ 1)
```

There are no guards (`f x | x > 0 = ...`): use `if`, `case`, or `with`. An `if` always
has an `else`. A type annotation inside an expression is `the Nat 3`.

Definitions are checked top to bottom, so a function must be declared before it is
used. For mutual recursion, give the signatures first or use a `mutual` block:

```idris
isEven : Nat -> Bool
isOdd : Nat -> Bool

isEven 0 = True
isEven (S k) = isOdd k

isOdd 0 = False
isOdd (S k) = isEven k
```

## Data types

```idris
data Colour = Red | Green | Blue

data Shape = Circle Double | Rect Double Double

data Tree a = Leaf | Node (Tree a) a (Tree a)

-- Indexed family: constructors are given with their full types.
data Expr : Type -> Type where
  IntLit  : Int -> Expr Int
  BoolLit : Bool -> Expr Bool
  Add     : Expr Int -> Expr Int -> Expr Int
  If      : Expr Bool -> Expr a -> Expr a -> Expr a

eval : Expr a -> a
eval (IntLit n) = n
eval (BoolLit b) = b
eval (Add x y) = eval x + eval y
eval (If c t e) = if eval c then eval t else eval e

-- A type synonym is an ordinary function that returns a type. Its name starts with
-- a capital, because a lowercase name in a type is read as a type variable.
Name : Type
Name = String

Pair' : Type -> Type
Pair' a = (a, a)
```

There is no `newtype` (use a one-constructor `data` or a `record`), no `type` keyword
and no `deriving` clause. An implementation is derived by an elaborator script, as a
named hint, after `import Deriving.Eq` (`Ord`, `Show`, also `DecEq`, `Functor`,
`Foldable`, `Traversable`):

```idris
%language ElabReflection

data Suit = Clubs | Diamonds | Hearts | Spades

%hint
eqSuit : Eq Suit
eqSuit = %runElab derive

%hint
ordSuit : Ord Suit                   -- constructors in the order of declaration
ordSuit = %runElab derive

%hint
showSuit : Show Suit
showSuit = %runElab derive

data Rose a = MkRose a (List (Rose a))

%hint
eqRose : Eq a => Eq (Rose a)         -- constraints are written as usual
eqRose = %runElab derive

trumps : List Suit
trumps = sort [Spades, Clubs, Hearts]
```

`Deriving.Eq`, `Ord` and `DecEq` are recent: if `import Deriving.Eq` gives `Module
Deriving.Eq not found`, the compiler predates them, and those three are written by hand
(next section).

## Records

```idris
record Point where
  constructor MkPoint
  x : Double
  y : Double

origin : Point
origin = MkPoint 0 0

norm1 : Point -> Double
norm1 p = abs p.x + abs p.y          -- p.x, or x p, or (.x) as a function

moveRight : Double -> Point -> Point
moveRight d p = { x $= (+ d) } p     -- $= applies a function to the field

reset : Point -> Point
reset = { x := 0, y := 0 }           -- := sets a field; the update is a function

record Counter (a : Type) where
  constructor MkCounter
  label : String
  count : Nat
  items : List a
```

## Interfaces

`interface` declares, a bare head implements. There is no `class` or `instance`.

```idris
interface HasArea a where
  areaOf : a -> Double
  describe : a -> String
  describe x = "area " ++ show (areaOf x)    -- default method

HasArea Shape where
  areaOf (Circle r) = pi * r * r
  areaOf (Rect w h) = w * h

Show Colour where
  show Red = "Red"
  show Green = "Green"
  show Blue = "Blue"

Eq Colour where
  Red == Red = True
  Green == Green = True
  Blue == Blue = True
  _ == _ = False

-- A constraint on the implementation, and one on a function.
Show a => Show (Tree a) where
  show Leaf = "Leaf"
  show (Node l v r) = "(" ++ show l ++ " " ++ show v ++ " " ++ show r ++ ")"

largest : Ord a => a -> List a -> a
largest = foldl max

-- A named implementation is used only when asked for with @{name}. Inside an
-- implementation of Ord Nat, `compare` on Nat means the implementation being
-- written, so the standard order is captured in a function defined before it.
flipped : Nat -> Nat -> Ordering
flipped a b = compare b a

[reversed] Ord Nat where
  compare = flipped

descending : List Nat -> List Nat
descending = sort @{reversed}

Functor Tree where
  map f Leaf = Leaf
  map f (Node l v r) = Node (map f l) (f v) (map f r)
```

The semigroup operator is `<+>` (there is no `<>`); `Monoid` adds `neutral`.

## Implicit arguments

A lowercase name in a type that is not bound anywhere becomes an implicit argument,
erased at run time. Bind it in braces when the function needs its value.

```idris
-- n and a are implicit and erased: usable in types only.
firstOf : Vect (S n) a -> a
firstOf (v :: _) = v

-- {n : Nat} keeps n at run time, so the body may return it.
lengthOf : {n : Nat} -> Vect n a -> Nat
lengthOf _ = n

three : Nat
three = lengthOf {n = 3} [1, 2, 3]            -- passing an implicit by name

-- An auto implicit is found by search, like an interface constraint.
safeHead : (xs : List a) -> {auto ok : NonEmpty xs} -> a
safeHead (v :: _) = v

-- A default implicit.
indentBy : {default 2 width : Nat} -> String -> String
indentBy s = replicate width ' ' ++ s

wide : String
wide = indentBy {width = 8} "text"
```

## `do` and effects

`pure` wraps a value (there is no `return`). The usual names: `traverse_`/`for_` for
a loop with effects, `traverse`/`for` to collect results, `when`, `unless`, `ignore`.

```idris
greet : IO ()
greet = do
  putStr "Name: "
  name <- getLine
  let shout = toUpper name               -- let in a do block has no `in`
  when (name /= "") $ putStrLn "Hello, \{shout}!"
  for_ [1 .. 3] $ \i => printLn (the Int i)

-- A failing pattern in a bind gets its alternative after `|`.
addStrings : String -> String -> Maybe Integer
addStrings a b = do
  Just m <- pure (parseInteger a)
    | Nothing => Nothing
  n <- parseInteger b
  pure (m + n)

-- `!e` runs the action e and uses its result; [| f a b |] is f <$> a <*> b.
addBang : Maybe Int -> Maybe Int -> Maybe Int
addBang a b = pure (!a + !b)

addIdiom : Maybe Int -> Maybe Int -> Maybe Int
addIdiom a b = [| a + b |]
```

Library functions that do IO have the type `HasIO io => ... -> io a`; they run in `IO`.

## Strings

`String` is a primitive type, not a list of characters.

```idris
describePoint : Point -> String
describePoint p = "(\{show p.x}, \{show p.y})"   -- interpolation takes a String

chars : String -> List Char
chars = unpack                                    -- pack goes back

shout : String -> String
shout s = toUpper s ++ "!"                        -- ++ joins strings and lists

initials : String -> String
initials = pack . mapMaybe (map fst . strUncons) . words

banner : String
banner = """
  Several lines; the indentation of the closing
  quotes is removed from every line.
  """

path : String
path = #"C:\dir\file with "quotes" and no \escapes"#
```

Useful names: `length` (a `Nat`), `words`, `unwords`, `lines`, `unlines`, `trim`,
`split`, `joinBy`, `isPrefixOf`, `isInfixOf`, `toUpper`, `toLower`, `strUncons`,
`substr`, `padLeft`; most need `import Data.String`.

## Numbers

| Type | What it is |
|---|---|
| `Integer` | arbitrary precision; the type of a literal when nothing else decides |
| `Int` | 64-bit machine integer (32-bit on the Node back end) |
| `Int8`…`Int64`, `Bits8`…`Bits64` | fixed width, signed and unsigned |
| `Nat` | natural number, `Z` and `S k` in patterns; the type of `length` |
| `Double` | floating point; `/` works only here |

```idris
average : List Int -> Double
average [] = 0
average xs = cast (sum xs) / cast (length xs)     -- cast converts between them

-- Nat has no (-): use minus (stops at 0), pred, or match on S.
countdown : Nat -> List Nat
countdown 0 = [0]
countdown (S k) = S k :: countdown k

halve : Integer -> Integer
halve n = n `div` 2                                -- div and mod, not / and %

readPort : String -> Maybe Nat
readPort = parsePositive                           -- parseInteger, parseDouble
```

## Collections

```idris
evens : List Int
evens = [x * 2 | x <- [1 .. 10], x `mod` 3 /= 0]   -- comprehension and range

firstOr : a -> List a -> a
firstOr d [] = d
firstOr _ (v :: _) = v

triple : (Int, String, Bool)                        -- a tuple is nested pairs
triple = (1, "one", True)

label : (Int, String, Bool) -> String
label (_, s, _) = s

vec : Vect 3 Int
vec = [1, 2, 3]

-- A dependent pair: a value and something whose type mentions it.
positives : Vect n Int -> (m ** Vect m Int)
positives [] = (0 ** [])
positives (v :: vs) =
  let (_ ** rest) = positives vs in
  if v > 0 then (_ ** v :: rest) else (_ ** rest)
```

`head` and `tail` on a `List` need a proof that the list is not empty; use pattern
matching, or `head'`, `last'`, `init'`, which return a `Maybe`. Indexing is `getAt`
(`Maybe`), or `index` with a `Fin` on a `Vect`.

## Operators

```idris
export infixl 6 |+|          -- a fixity declaration; `export` lets importers use it

(|+|) : Point -> Point -> Point
p |+| q = MkPoint (p.x + q.x) (p.y + q.y)

squares : List Int
squares = map (\v => v * v) $ filter (> 0) [3, -1, 2]

minusOne : List Int -> List Int
minusOne = map (\v => v - 1)     -- (- 1) is the number, not a section; or (`minus` 1)
```

Function composition is `.`, application `$`, as in Haskell; also `<$>`, `<*>`, `>>=`,
`<|>`, `&&`, `||`, `not`, `==`, `/=`.

## Visibility, totality, namespaces

A definition is private to its namespace unless marked. `export` shows the name and
type; `public export` also shows the body, which a type checker in another module needs
whenever the definition is used in a type (type synonyms, functions in indices).

```idris
namespace Stack
  export
  data Stack a = MkStack (List a)       -- type visible, constructor hidden

  export
  empty : Stack a
  empty = MkStack []

  export
  push : a -> Stack a -> Stack a
  push v (MkStack vs) = MkStack (v :: vs)

  public export
  Depth : Type
  Depth = Nat

total
safeDiv : Int -> Int -> Maybe Int
safeDiv _ 0 = Nothing
safeDiv a b = Just (assert_total (a `div` b))

covering
collatz : Nat -> Nat
collatz 1 = 0
collatz n = S (collatz (if n `mod` 2 == 0 then n `div` 2 else 3 * n + 1))
```

`total` means: covers all inputs and terminates. `covering` (the default) means: covers
all inputs. `partial` promises nothing. `%default total` sets the default for a file.

A block of definitions that share arguments:

```idris
parameters (sep : String)
  joinTwo : String -> String -> String
  joinTwo a b = a ++ sep ++ b

  joinAll : List String -> String
  joinAll = joinBy sep

dashed : String
dashed = joinAll "-" ["a", "b"]         -- outside, the parameter comes first
```

## Dependent types

```idris
append : Vect n a -> Vect m a -> Vect (n + m) a
append [] ys = ys
append (v :: vs) ys = v :: append vs ys

zipSame : Vect n a -> Vect n b -> Vect n (a, b)
zipSame [] [] = []
zipSame (v :: vs) (w :: ws) = (v, w) :: zipSame vs ws

-- `with` matches on a computed value; the bar repeats the left-hand side.
keepSmall : Nat -> List Nat -> List Nat
keepSmall limit [] = []
keepSmall limit (v :: vs) with (v <= limit)
  keepSmall limit (v :: vs) | True = v :: keepSmall limit vs
  keepSmall limit (v :: vs) | False = keepSmall limit vs

-- An equality proof, and a clause that cannot happen.
plusZero : (n : Nat) -> n + 0 = n
plusZero 0 = Refl
plusZero (S k) = cong S (plusZero k)

noNatBelowZero : (n : Nat) -> LT n 0 -> Void
noNatBelowZero _ prf impossible

-- A hole stands for a missing expression; the file still checks.
todo : Vect n a -> Vect n a
todo xs = ?todo_rhs
```

Proofs, `rewrite`, views and totality techniques are in the `idris2i-1-proofs` skill.

## Laziness

Evaluation is strict: arguments are computed before a call. `Lazy a` delays one
argument (the compiler inserts `Delay` and `Force`); `Inf` marks the recursive argument
of an infinite structure.

```idris
orElse : Maybe a -> Lazy a -> a
orElse (Just v) _ = v
orElse Nothing d = d

countFrom : Nat -> Stream Nat
countFrom n = n :: countFrom (S n)

firstFive : List Nat
firstFive = take 5 (countFrom 0)
```

## Pragmas

| Pragma | Use |
|---|---|
| `%default total` | totality default for the file (`covering`, `partial`) |
| `%inline`, `%noinline` | on a definition, for the code generator |
| `%hint` | on a function: use it in `auto` search |
| `%foreign "C:name,lib"` | bind a foreign function (see the `idris2i-1-ffi` skill) |
| `%language ElabReflection` | needed before `%runElab` |
| `%unbound_implicits off` | stop binding lowercase names automatically |
| `%hide Name` | hide an imported name that clashes |
| `%name Type x, y` | names the compiler uses when it generates clauses |

`idris2i-1 --help pragma` lists all of them.
