# Habits from Haskell and Idris 1 that fail in Idris 2

Each wrong form below is inside a `failing` block, which the compiler checks: the code
does fail, and with the quoted message. Search this file for the message you got.
Forms that do not even parse cannot be put in a `failing` block; they are shown as
`text` and listed with the message of the parser.

<!-- idris
import Data.List
import Data.Nat
import Data.String
import Data.Vect
-->

Contents: [syntax that does not parse](#syntax-that-does-not-parse) ·
[names that do not exist](#names-that-do-not-exist) · [strings](#strings) ·
[numbers](#numbers) · [lists](#lists) · [types and implicit arguments](#types-and-implicit-arguments) ·
[local definitions and order](#local-definitions-and-order) · [data and records](#data-and-records) ·
[interfaces](#interfaces) · [visibility](#visibility) · [totality](#totality) ·
[IO](#io) · [Idris 1](#idris-1)

## Syntax that does not parse

A parse error stops the file at the first one, and its message names the token the
parser wanted, not the habit that caused it.

| Written | Message | Idris 2 form |
|---|---|---|
| `f :: Int -> Int` | `Couldn't parse declaration.` | `f : Int -> Int` |
| `\x -> x + 1` | `Expected '=>'.` | `\x => x + 1` |
| `case x of 0 -> "a"` | `Expected '=>' or 'impossible'.` | `0 => "a"` |
| `f x \| x > 0 = 1` (guard) | `Expected end of input.` | `if`, `case` or `with` |
| `if c then a` | `Expected 'else'.` | always give the `else` |
| `xs !! 0`, `a <> b`, `2 ^ 10` | `Unknown operator '!!'` | `getAt`, `<+>`, `power` / `pow` |
| `%access public export` | `Couldn't parse declaration.` | mark each definition |
| an `import` after a declaration | `Imports must go before any declarations or directives.` | move it to the top |

Keywords cannot be variable or field names, and the parser's message does not say so:
`let total = ...` gives `Not the end of a block entry, check indentation` or `Couldn't
parse any alternatives`. The ones that are easy to reach for: `total`, `default`,
`proof`, `auto`, `open`, `prefix`, `infix`, `using`, `implicit`, `parameters`, `data`,
`record`, `partial`, `covering`, `public`, `private`, `export`, `failing`.

The guard message is the least helpful one: when `Expected end of input` points at a
`|` on a function clause, the clause has a Haskell guard.

## Names that do not exist

All of these give `Undefined name ...` (E0201). The compiler often adds the module to
import; when it does not, this table has the replacement.

| Haskell | Idris 2 |
|---|---|
| `return` | `pure` |
| `mapM_`, `forM_` | `traverse_`, `for_` |
| `mapM`, `forM` | `traverse`, `for` |
| `print x` (with newline) | `printLn x`; `print` exists and writes no newline |
| `read` | `parsePositive`, `parseInteger`, `parseDouble` (`Data.String`), giving a `Maybe` |
| `fromIntegral`, `toInteger` | `cast` |
| `error "msg"` | return a `Maybe`/`Either`; `idris_crash "msg"` is `partial`, so even a `covering` function must wrap it: `assert_total (idris_crash "msg")` |
| `undefined` | a hole, `?todo` |
| `otherwise` | `True`, or an `else` |
| `seq`, `$!`, bang patterns | not needed: evaluation is strict |
| `maximum xs`, `minimum xs` | `foldl max start xs`; `maximum` is the two-argument one on `Nat` |
| `sortOn f` | `sortBy (comparing f)` |
| `Data.Map`, `Data.Set` | `Data.SortedMap`, `Data.SortedSet` (keys need `Ord`) |
| `concat`/`<>` on strings | `++`, `<+>`, `concat`, `fastConcat` |
| `even`, `odd` | `import Data.Integral`, or `` n `mod` 2 == 0 `` |
| `import Data.Char`, `Data.Foldable`, `Data.Ord` | not modules here: `isDigit`, `isAlpha`, `isSpace`, `ord`, `chr`, `traverse_`, `comparing` are in the Prelude |
| `x .&. y`, `shiftR x n` | `import Data.Bits`; the shift amount is a `Fin`, so a literal works and an `Int` does not (`Can't find an implementation for Cast Int (Fin 32)`) |

```idris
failing "Undefined name return"
  one : IO Int
  one = return 1

failing "Undefined name mapM_"
  showAll : List Int -> IO ()
  showAll xs = mapM_ printLn xs

failing "Mismatch between: List Int and Nat"
  biggest : List Int -> Int
  biggest xs = maximum xs                  -- Data.Nat.maximum : Nat -> Nat -> Nat

biggest : List Int -> Int
biggest = foldl max 0

byLength : List String -> List String
byLength = sortBy (comparing length)
```

Do not guess a library name. Ask the compiler (`:doc`, `:search`, `:browse`; see
`toolchain.md`), because a name that exists in Haskell may exist here with another
type: `maximum : Nat -> Nat -> Nat`, `head : (l : List a) -> {auto 0 _ : NonEmpty l} -> a`,
`split : (Char -> Bool) -> String -> List1 String`.

## Strings

`String` is primitive. List functions do not apply to it, and a string literal is not
a list.

```idris
failing "Mismatch between: String and List"
  firstChar : String -> Maybe Char
  firstChar s = head' s

firstChar : String -> Maybe Char
firstChar s = map fst (strUncons s)        -- or: head' (unpack s)

failing "Can't find an implementation for Interpolation Nat"
  report : Nat -> String
  report n = "count: \{n}"

report : Nat -> String
report n = "count: \{show n}"              -- an interpolated value is a String

failing "Mismatch between: Int and String"
  label : Int -> String
  label n = "n = " ++ n

label : Int -> String
label n = "n = " ++ show n
```

`toUpper` and `toLower` exist for `Char` (Prelude) and for `String` (`Data.String`);
`reverse` and `length` work on a `String` directly.

## Numbers

A literal is an `Integer` unless its context says otherwise, `length` returns a `Nat`,
and nothing converts by itself: `cast` does.

```idris
failing "Mismatch between: Nat and Int"
  total' : Int -> List a -> Int
  total' base xs = base + length xs

total' : Int -> List a -> Int
total' base xs = base + cast (length xs)

failing "Can't find an implementation for Neg Nat"
  lastIndex : List a -> Nat
  lastIndex xs = length xs - 1

lastIndex : List a -> Nat
lastIndex xs = pred (length xs)            -- or: length xs `minus` 1

failing "Can't find an implementation for Fractional Int"
  half : Int -> Int
  half n = n / 2

half : Int -> Int
half n = n `div` 2

failing "Can't find an implementation for Num (Int -> Int)"
  decAll : List Int -> List Int
  decAll = map (- 1)                       -- (- 1) is the number minus one

decAll : List Int -> List Int
decAll = map (\n => n - 1)

failing "Not a constructor application or primitive"
  predOf : Nat -> Nat
  predOf (n + 1) = n
  predOf 0 = 0

predOf : Nat -> Nat
predOf (S n) = n
predOf 0 = 0
```

Powers: `power base exponent` with a `Nat` exponent (`Data.Nat`), `pow` on `Double`.

## Lists

```idris
failing "Can't find an implementation for NonEmpty xs"
  firstElem : List Int -> Int
  firstElem xs = head xs

firstElem : List Int -> Int
firstElem [] = 0
firstElem (x :: _) = x

failing "Can't find an implementation for Num (Int, Int)"
  third : (Int, Int, Int) -> Int
  third (_, _, c) = c

  two : Int
  two = third (1, 2)                       -- (a, b, c) is (a, (b, c))
```

With `Data.Vect` imported, `[1, 2, 3]` can be a `List` or a `Vect`. Where only a
`Foldable` or `Functor` is asked for, the compiler reports `Ambiguous elaboration`
(E0301); say which one with `the (List Int) [1, 2, 3]`, or give the binding a type.

```idris
failing "Ambiguous elaboration"
  printThree : IO ()
  printThree = for_ [1, 2, 3] $ \i => printLn (the Int i)

printThree : IO ()
printThree = for_ (the (List Int) [1, 2, 3]) printLn
```

A range counts down when its end is below its start: `[1 .. 0]` is `[1, 0]`, not the
empty list, so `for_ [0 .. n - 1]` runs twice for `n = 0`. Guard the empty case, or
count with `take n [0 ..]`.

```idris
countsDown : the (List Int) [1 .. 0] = [1, 0]
countsDown = Refl

firstN : Nat -> List Nat
firstN n = take n [0 ..]                   -- [] for 0
```

The list type is `List a`; `[a]` is a one-element list holding the type `a`, and
gives `Sorry, I can't find any elaboration which works` (E0302) in a signature.

## Types and implicit arguments

A lowercase name in a type is a type variable even when a definition with that name
exists. The compiler warns (W0003, "We are about to implicitly bind the following
lowercase names"), and the error that follows mentions the name as if it were unknown.

```idris
namespace Lower
  size : Nat
  size = 3

  failing "Mismatch between: S ?len and size"
    row : Vect size Int                    -- size here is a new variable
    row = [1, 2, 3]

namespace Upper
  Size : Nat
  Size = 3

  row : Vect Size Int                      -- capitalised, or qualified: Upper.Size
  row = [1, 2, 3]
```

Such an implicit argument is erased: it exists while type checking and not at run
time, so the body cannot return it or match on it.

```idris
failing "n is not accessible in this context"
  len : Vect n a -> Nat
  len xs = n

len : {n : Nat} -> Vect n a -> Nat         -- bound in braces: kept at run time
len xs = n
```

A type annotation in an expression is `the Nat 3`. Haskell's `(3 :: Nat)` builds a
list and fails with `Sorry, I can't find any elaboration which works`.

## Local definitions and order

A local function without a signature gets a type guessed from its body, with numeric
literals fixed to `Integer`. Give local functions their signatures.

```idris
failing "Mismatch between: Int and Integer"
  bump : Int -> Int
  bump x = go x
    where
      go y = y + 1

bump : Int -> Int
bump x = go x
  where
    go : Int -> Int
    go y = y + 1
```

A name must be declared before the line that uses it. For mutual recursion write both
signatures first (or a `mutual` block).

```idris
failing "Undefined name isOdd'"
  isEven' : Nat -> Bool
  isEven' 0 = True
  isEven' (S k) = isOdd' k

  isOdd' : Nat -> Bool
  isOdd' 0 = False
  isOdd' (S k) = isEven' k
```

## Data and records

A record field is also a function, so a field called `sum`, `length` or `id` hides the
Prelude function of that name in the rest of the module: after `record Reply where sum
: Integer`, the expression `sum xs` is a type error ("Mismatch between: List Integer
and Reply"). Qualify the library function (`Prelude.sum xs`) or pick another field name.

| Written | Message | Idris 2 form |
|---|---|---|
| `data C = R \| G deriving (Show, Eq)` | `Mismatch between: Type -> Type and Type` | no `deriving` clause: `%runElab derive` (`syntax.md`, data types), or write the implementation |
| `type Name = String` | `No type declaration for Main.type` | `Name : Type` and `Name = String` |
| `newtype Age = MkAge Int` | `No type declaration for Main.newtype` | `data Age = MkAge Int` or a `record` |
| `p { x = 1 }` | `x is not a valid argument in p` | `{ x := 1 } p` |

```idris
record Config where
  constructor MkConfig
  port : Nat
  host : String

failing "port is not a valid argument in c"
  setPort : Config -> Config
  setPort c = c { port = 8080 }

setPort : Config -> Config
setPort c = { port := 8080 } c             -- $= to apply a function to the field
```

## Interfaces

```idris
failing "Undefined name class"
  class Pretty a where
    pretty : a -> String

interface Pretty a where
  pretty : a -> String

failing "Undefined name instance"
  instance Pretty Bool where
    pretty b = show b

Pretty Bool where
  pretty b = show b
```

Inside an implementation, a call of the method at the same type is a call of the
implementation being written. An implementation that wants the standard behaviour
"with a twist" loops, and the totality checker says so (E0704, "possibly not
terminating due to recursive path"). Capture the standard behaviour in a function
defined before the implementation:

```idris
backwards : Nat -> Nat -> Ordering
backwards a b = compare b a

[downward] Ord Nat where
  compare = backwards
```

An implementation is checked for coverage like any function: a `Show` with a missing
constructor is an error (E0601), not a run-time failure.

## Visibility

Everything is private to its namespace or module unless marked. `export` publishes the
name and type. `public export` also publishes the definition, and that is what another
module needs to compute with it in a type.

```idris
namespace Lib
  export
  two : Nat
  two = 2

  public export
  three : Nat
  three = 3

  secret : Nat
  secret = 1

failing "Name Main.Lib.secret is private"
  leak : Nat
  leak = Lib.secret

failing "Can't solve constraint between: 2 and two"
  pair : Vect Lib.two Int                  -- two does not reduce outside Lib
  pair = [1, 2]

triple : Vect Lib.three Int
triple = [1, 2, 3]
```

Rule of thumb: types, type synonyms, and functions that appear in other definitions'
types are `public export`; everything else that is part of the API is `export`. A
`public export` definition can only mention names that are themselves visible.

## Totality

The default is `covering`: all cases handled, termination not checked. Under `total`
or `%default total` three things surprise:

1. `div` and `mod` are not total (division by zero), so a `total` function that uses
   them is rejected with `is not covering` (E0602; this fork). Use `divNatNZ` and
   `modNatNZ` on `Nat`, or check the divisor and wrap the call in `assert_total`.
2. Recursion must be on a part of an argument that the checker can see is smaller.
   `f (x :: xs) = ... f (filter p xs)` is rejected; so is recursion through `map`.
3. Reading input in a loop forever is not total. Mark the loop `covering`.

```idris
failing "is not covering"
  total
  halfOf : Nat -> Nat
  halfOf n = n `div` 2

total
halfOf : Nat -> Nat
halfOf n = divNatNZ n 2 %search            -- %search finds the proof that 2 is not 0
```

The `idris2-proofs` skill has the techniques (`Fuel`, views, well-founded recursion).

## IO

- `readFile` (in `System.File`) returns `Either FileError String`; match on it.
- Functions on files, arguments and exit codes need imports: `System` (`getArgs`,
  `exitWith`, `exitFailure`, `die`, `getEnv`), `System.File`, `Data.IORef`.
- `print` writes no newline; `printLn` does.
- Writing to standard error is `fPutStrLn stderr msg` (`System.File`), and it returns
  `Either FileError ()`. As a bare statement it fails with "Can't find an
  implementation for HasIO ?io"; write `ignore (fPutStrLn stderr msg)` or
  `_ <- fPutStrLn stderr msg`. `die msg` prints to standard error and exits with 1.
- There are no exceptions to catch in `IO`: failure is a value (`Maybe`, `Either`).

```idris
failing "Mismatch between: Either"
  firstLine : Either String String -> String
  firstLine contents = fromMaybe "" (head' (lines contents))

firstLine : Either String String -> String
firstLine (Left err) = "error: " ++ err
firstLine (Right contents) = fromMaybe "" (head' (lines contents))
```

## Idris 1

| Idris 1 | Idris 2 |
|---|---|
| `%access export` | no such directive; mark each definition |
| `public`, `abstract` | `public export`, `export` |
| `record { field = v } r` | `{ field := v } r` |
| `f {n} xs = n` with `f : Vect n a -> Nat` | bind it in the type: `f : {n : Nat} -> ...` |
| tactics, `proof { ... }`, `%elim` | none; write the term, with `rewrite` and holes |
| `postulate`, `codata`, `syntax` rules, `implicit` conversions | gone (`believe_me`, `Inf`, plain functions, `cast`) |
| the `Effects` library | `Control.App`, or monad transformers in `Control.Monad.*` |
| `Force`/`Delay` written by hand | inserted by the compiler for `Lazy` and `Inf` |
| a definition used at type level just works | it must be `public export` |
| everything `total` unless `partial` | default is `covering`; ask with `total` |
| code from *Type-Driven Development with Idris* | needs small changes: signatures on local functions, `{n : Nat}` where an index is used, `%default total` |
