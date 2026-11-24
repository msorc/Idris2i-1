# Text: strings, numbers, parsers, pretty printing, options

Every example is a complete program: its imports are in the first block, and
`main = exStrings` (or another example) runs it. `Data.String` is in `base`; the
parsers, `Text.PrettyPrint.Prettyprinter` and `System.Console.GetOpt` are in
`contrib` (`-p contrib`).

```idris
import Data.List
import Data.List1
import Data.String
import Data.String.Parser
import System
import System.Console.GetOpt
import Text.Lexer
import Text.Parser
import Text.PrettyPrint.Prettyprinter
import Text.PrettyPrint.Prettyprinter.Render.String
```

## `String` is not a list

`String` is a primitive (UTF-8 on RefC), not `List Char`: no pattern matching on
`x :: xs`, and `++` is `String`'s own. Convert with `unpack : String -> List Char`
and `pack`, or match with `strM`/`asList` views. `length` is `Nat`;
`strLength`, `strIndex`, `strSubstr` work on `Int` positions.

```idris
failing "Mismatch between: List ?a and String"
  firstChar : String -> Maybe Char
  firstChar s = case s of
    (c :: _) => Just c
    [] => Nothing
```

```idris
firstChar : String -> Maybe Char
firstChar s = case strM s of
  StrCons c _ => Just c
  StrNil => Nothing
```

## `Data.String`

| want | write | note |
|---|---|---|
| split on a character | `split (== ',') s` | takes a predicate; returns `List1 String`, use `forget` |
| lines / words | `lines s`, `words s`, `unlines`, `unwords` | |
| join | `joinBy ", " xs` | not `intercalate` (that is for lists: `pack (intercalate ...)`) |
| trim | `trim`, `ltrim`, `rtrim` | |
| prefix / suffix / infix | `isPrefixOf "ab" s`, `isSuffixOf`, `isInfixOf` | `Data.String`'s, on `String` |
| case | `toUpper`, `toLower` | |
| pad | `padLeft 5 '0' s`, `padRight` | |
| one character | `singleton c` | |
| substring | `strSubstr start len s` | `Int`s |
| `Show` without quotes | `show 3`, but for `String` use the value | `show "a"` is `"\"a\""` |

String interpolation is `"x = \{show x}"`; the expression must be a `String`.

```idris
exStrings : IO ()
exStrings = do
  let csv = " ann, 31 ,bob,7 "
      fields = map trim (forget (split (== ',') csv))
  printLn fields                                  -- ["ann", "31", "bob", "7"]
  putStrLn (joinBy "|" fields)                    -- ann|31|bob|7
  printLn (words "  two   words ")                -- ["two", "words"]
  printLn ("ann" `isPrefixOf` "anne", "x" `isInfixOf` "abc")
  putStrLn (padLeft 5 '0' (show 42))              -- 00042
  printLn (unpack "hé")                           -- ['h', '\233']
```

## Numbers from strings

`cast {to = Int} "12x"` returns `0` on bad input and wraps a number too large
for `Int`, silently. Use the `Data.String`
parsers, which return `Maybe`:

- `parsePositive : Num a => String -> Maybe a`: digits, an optional `+`, no `-`.
- `parseInteger : (Num a, Neg a) => String -> Maybe a`: optional `-` or `+`.
- `parseDouble : String -> Maybe Double`.

All of them accept surrounding spaces and reject trailing garbage. Pin the result
type, as the type decides the instance.

```idris
exNumbers : IO ()
exNumbers = do
  printLn (parsePositive {a = Nat} "42")         -- Just 42
  printLn (parsePositive {a = Int} "-42")        -- Nothing
  printLn (parseInteger {a = Int} "-42")         -- Just (-42)
  printLn (parseInteger {a = Integer} "12x")     -- Nothing
  printLn (parseDouble "3.5e2")                  -- Just 350.0
  printLn (cast {to = Int} "12x")                -- 0: no error
```

## `Data.String.Parser` (contrib): parser combinators on `String`

A small Parsec: `Parser a`, `parse p s : Either String (a, Int)` (the result and
the position where it stopped). `char`, `string`, `satisfy`, `digit`,
`natural`, `integer`, `spaces`, `lexeme p` (`p` then spaces), `token "x"`,
`sepBy`, `commaSep`, `many`, `some`, `optional`, `option`, `between`,
`parens`, `eos` (end of input), `<|>`, `<?>` (label an error). `takeWhile` and
`takeWhile1` return `String`s.

```idris
data KV = MkKV String Integer

Show KV where
  show (MkKV k v) = k ++ "=" ++ show v

key : Parser String
key = lexeme (takeWhile1 isAlpha) <?> "a key"

pair : Parser KV
pair = do
  k <- key
  token "="
  v <- lexeme integer
  pure (MkKV k v)

pairs : Parser (List KV)
pairs = spaces *> sepBy pair (token ";") <* eos

exParser : IO ()
exParser = do
  printLn (map fst (parse pairs "a = 1; bc = -20 ;d=3"))
  printLn (map fst (parse pairs "a = x"))
  -- Left "Parse failed at position 0-0: expected the end of the string":
  -- sepBy gave up on "a = x" and returned [], then eos failed
```

`Data.String.Parser.Expression` builds operator tables.

## `Text.Lexer` and `Text.Parser` (contrib): a lexer and a grammar

For a real language: a lexer turns the input into tokens with positions, a
`Grammar` parses the tokens and knows statically whether a rule consumes input
(the `True`/`False` index), which makes `many` over a rule that may consume
nothing a type error rather than a loop.

```idris
data Kind = Num | Plus | Space

Eq Kind where
  Num == Num = True
  Plus == Plus = True
  Space == Space = True
  _ == _ = False

TokenKind Kind where
  TokType Num = Integer
  TokType _ = ()
  tokValue Num s = cast s
  tokValue Plus _ = ()
  tokValue Space _ = ()

tokens : TokenMap (Token Kind)
tokens = toTokenMap [(digits, Num), (is '+', Plus), (spaces, Space)]

sumExpr : Grammar () (Token Kind) True Integer
sumExpr = do
  n <- match Num
  ns <- many (match Plus *> match Num)
  pure (foldl (+) n ns)

calc : String -> Either String Integer
calc s =
  let (toks, _, _, rest) = lex tokens s in
  if rest /= "" then Left "cannot lex: \{rest}" else
  case parse sumExpr (filter (\t => t.val.kind /= Space) toks) of
    Right (v, []) => Right v
    Right (_, more) => Left "unexpected tokens"
    Left errs => Left (show (map (\(Error msg _) => msg) errs))

exLexer : IO ()
exLexer = do
  printLn (calc "1 + 2 + 30")         -- Right 33
  printLn (calc "1 + + 2")
  printLn (calc "1 ? 2")
```

## `Text.PrettyPrint.Prettyprinter` (contrib)

The `prettyprinter` package of Haskell: `pretty x` (`Pretty` interface), `<+>`
(with a space), `<++>`, `vsep`, `hsep`, `sep`, `nest`, `indent`, `group`,
`parens`, `brackets`, `encloseSep`, `line`, `softline`. Render with
`renderString (layoutPretty defaultLayoutOptions doc)`, or `show doc` (80 columns).

```idris
record Fn where
  constructor MkFn
  name : String
  args : List String
  body : List String

prettyFn : Fn -> Doc ()
prettyFn f =
  vsep [ pretty "def" <++> pretty f.name <+> tupled (map pretty f.args) <+> pretty ":"
       , indent 4 (vsep (map pretty f.body)) ]

exPretty : IO ()
exPretty = do
  let doc = prettyFn (MkFn "add" ["x", "y"] ["z = x + y", "return z"])
  putStrLn (renderString (layoutPretty defaultLayoutOptions doc))
  let narrow = MkLayoutOptions (AvailablePerLine 20 1)
      words12 : Doc () = group (vsep (map pretty (words "a b c d e f g h i j k l")))
  putStrLn (renderString (layoutPretty narrow words12))    -- too wide: one per line
  putStrLn (renderString (layoutPretty defaultLayoutOptions words12))  -- fits
```

`Text.PrettyPrint.Prettyprinter.Render.Terminal` adds ANSI colours.

## `System.Console.GetOpt` (contrib): command-line options

The `GetOpt` of Haskell's `base`. Describe each option with `MkOpt shortNames
longNames argDescr help`; `getOpt Permute options args` gives a `Result` record
with `options`, `nonOptions`, `unrecognized` and `errors`. Pass `getArgs` without
the program name (`drop 1`).

```idris
data Flag = Verbose | Output String | Level Nat

opts : List (OptDescr Flag)
opts =
  [ MkOpt ['v'] ["verbose"] (NoArg Verbose) "say more"
  , MkOpt ['o'] ["output"] (ReqArg Output "FILE") "write to FILE"
  , MkOpt ['l'] ["level"]
      (ReqArg' (\s => maybe (Left "bad level: \{s}") (Right . Level) (parsePositive s)) "N")
      "level, a number"
  ]

record Config where
  constructor MkConfig
  verbose : Bool
  output : String
  level : Nat

apply : Config -> Flag -> Config
apply c Verbose = { verbose := True } c
apply c (Output f) = { output := f } c
apply c (Level n) = { level := n } c

exOptions : IO ()
exOptions = do
  args <- getArgs
  let res = getOpt Permute opts (drop 1 args)
  case res.errors ++ map ("unknown option " ++) res.unrecognized of
    [] => pure ()
    errs => do
      putStr (unlines errs)
      putStr (usageInfo "usage: prog [OPTIONS] FILES" opts)
      exitFailure
  let cfg = foldl apply (MkConfig False "-" 0) res.options
  putStrLn "verbose=\{show cfg.verbose} output=\{cfg.output} level=\{show cfg.level} files=\{show res.nonOptions}"
```
