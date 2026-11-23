# JSON and deriving

Every example is a complete program: its imports are in the first block, and
`main = exDerive` (or another example) runs it. JSON is in `contrib`
(`-p contrib`); the typed layer (`Language.JSON.Typed`, `.Derive`, `.Encode`,
`.Parse`) is this fork's: upstream 0.8 has only `Language.JSON` with `parse` and
`Show`. `Deriving.*` is in `base`.

```idris
import Data.ByteString
import Data.List
import Data.SortedMap
import Data.String
import Deriving.DecEq
import Deriving.Eq
import Deriving.Foldable
import Deriving.Functor
import Deriving.Ord
import Deriving.Show
import Deriving.Traversable
import Language.JSON
import Language.JSON.Derive

%language ElabReflection
```

`Language.JSON.Derive` re-exports `Language.JSON.Typed`, which re-exports
`.Encode`, `.Parse`, `.Data` and `Data.ByteString.Builder`. Every `%runElab`
needs `%language ElabReflection` in the file.

## The modules

| module | has |
|---|---|
| `Language.JSON` | `data JSON = JNull \| JBoolean Bool \| JNumber Double \| JString String \| JArray (List JSON) \| JObject (List (String, JSON))`; `parse : String -> Maybe JSON`, `parseEither`, `parseByteString`; `lookup key json`, `format indent json` |
| `Language.JSON.Parse` | `parseBytes : ByteString -> Either JSONError JSON`, `parseText`, `errorLocation` (line, column) |
| `Language.JSON.Encode` | `encode : JSON -> ByteString`, `encodeText : JSON -> String` (compact, correct escapes) |
| `Language.JSON.Typed` | `interface ToJSON a` (`toJSON`), `interface FromJSON a` (`fromJSON : JSON -> Either DecodeError a`); `toJSONText`, `toJSONBytes`, `fromJSONText`, `fromJSONBytes`; helpers `withObject`, `field`, `optionalField`, `withString`, `failDecode` |
| `Language.JSON.Derive` | `deriveToJSON`, `deriveFromJSON` with `defaultOptions` |

Instances exist for `()`, `Bool`, `Char`, `String`, `Double`, `Int`, `Integer`,
`Nat`, the fixed-width integers (range checked), `Maybe`, `List`, `List1`,
`SnocList`, `Vect n`, pairs (arrays of two), `Either` (`{"Left": ...}`),
`SortedMap String v` and `HashMap String v` (objects), and `JSON` itself.
Numbers are `Double`s: integers above 2^53 lose precision.

Use `encodeText`/`toJSONText` to produce JSON, not `show`: `Show JSON` writes text
that is not JSON for infinities and characters above U+FFFF.

## Derive a codec

Derived instances are bound with `%hint` (they are named values, not
`implementation` blocks). A record becomes an object with its field names; a
`Maybe` field may be missing; an enumeration becomes a string; a sum type becomes
`{"tag": "Con", "contents": ...}` (or the fields of a record-like constructor
beside `"tag"`), as Haskell's `aeson` does. Indexed families, existential, erased
and lazy fields are rejected with a message.

```idris
data Role = Admin | Member | Guest

record User where
  constructor MkUser
  name : String
  age : Int
  role : Role
  email : Maybe String
  tags : List String

%hint roleTo : ToJSON Role
roleTo = %runElab deriveToJSON defaultOptions
%hint roleFrom : FromJSON Role
roleFrom = %runElab deriveFromJSON defaultOptions
%hint userTo : ToJSON User
userTo = %runElab deriveToJSON defaultOptions
%hint userFrom : FromJSON User
userFrom = %runElab deriveFromJSON defaultOptions

%hint roleShow : Show Role
roleShow = %runElab derive
%hint userShow : Show User
userShow = %runElab derive

exDerive : IO ()
exDerive = do
  let u = MkUser "ann" 41 Admin Nothing ["a", "b"]
  putStrLn (toJSONText u)
  -- {"name":"ann","age":41,"role":"Admin","email":null,"tags":["a","b"]}
  printLn (fromJSONText {a = User} "{\"name\":\"bob\",\"age\":7,\"role\":\"Guest\",\"tags\":[]}")
  -- Right (MkUser "bob" 7 Guest Nothing [])
  case fromJSONText {a = User} "{\"name\":\"bob\",\"age\":\"7\",\"role\":\"Guest\",\"tags\":[]}" of
    Right v => printLn v
    Left err => putStrLn "bad input: \{show err}"
  -- bad input: at $.age: expected an integer (Int), got a string
  printLn (fromJSONText {a = Role} "\"Owner\"")
  printLn (fromJSONText {a = User} "{\"name\":")
```

A record field is also a top-level function of the module: a field called
`sum`, `length`, `id` or `max` hides the Prelude function of that name in the
rest of the module, and `sum xs` then fails with "Mismatch between: List
Integer and Reply" (the field's record type). Write `Prelude.sum xs`, or name
the field otherwise (a JSON key can be renamed with `fieldName`, below).

```idris
failing "Mismatch between: List Integer and Reply"
  record Reply where
    constructor MkReply
    sum : Integer
  mkReply : List Integer -> Reply
  mkReply xs = MkReply (sum xs)
```

`fromJSONText`/`fromJSONBytes` parse and decode in one step; a syntax error is a
`Syntax` `DecodeError`, a shape error a `Mismatch` with the JSONPath of the part
that did not fit. Unknown members are ignored.

`Options` renames: `fieldName : String -> String` (keys), `constructorTag`,
`tagField` (default `"tag"`), `contentsField` (default `"contents"`):

```idris
record Config where
  constructor MkConfig
  maxConnections : Int
  hostName : String

snake : String -> String
snake = pack . concatMap (\c => if isUpper c then ['_', toLower c] else [c]) . unpack

%hint configTo : ToJSON Config
configTo = %runElab deriveToJSON ({ fieldName := snake } defaultOptions)
%hint configFrom : FromJSON Config
configFrom = %runElab deriveFromJSON ({ fieldName := snake } defaultOptions)

exOptions : IO ()
exOptions = do
  putStrLn (toJSONText (MkConfig 10 "localhost"))
  -- {"max_connections":10,"host_name":"localhost"}
  printLn (map (.hostName) (fromJSONText {a = Config} "{\"max_connections\":1,\"host_name\":\"h\"}"))
```

## Write an instance by hand

The constructors are `MkToJSON` and `MkFromJSON` with extra fields for the fast
paths, so write `ToJSON`/`FromJSON` as ordinary `implementation`s and give only
`toJSON` and `fromJSON`: the other methods have defaults.

```idris
record Version where
  constructor MkVersion
  major : Int
  minor : Int

-- As the string "1.2"
ToJSON Version where
  toJSON v = JString "\{show v.major}.\{show v.minor}"

FromJSON Version where
  fromJSON = withString "Version" $ \s =>
    case forget (split (== '.') s) of
      [a, b] => case (parseInteger a, parseInteger b) of
        (Just x, Just y) => Right (MkVersion x y)
        _ => failDecode "expected two numbers"
      _ => failDecode "expected MAJOR.MINOR"

record Pkg where
  constructor MkPkg
  name : String
  version : Version

ToJSON Pkg where
  toJSON p = JObject [("name", toJSON p.name), ("version", toJSON p.version)]

FromJSON Pkg where
  fromJSON = withObject "Pkg" $ \o => [| MkPkg (field o "name") (field o "version") |]

exManual : IO ()
exManual = do
  putStrLn (toJSONText (MkPkg "http" (MkVersion 0 8)))
  printLn (map (.version.minor) (fromJSONText {a = Pkg} "{\"name\":\"x\",\"version\":\"1.12\"}"))
  printLn (map (.name) (fromJSONText {a = Pkg} "{\"name\":\"x\",\"version\":\"1\"}"))
```

## The untyped `JSON` value

```idris
exValue : IO ()
exValue = do
  Right j <- pure (parseEither "{\"a\": [1, 2.5, null], \"b\": {\"c\": true}}")
    | Left e => putStrLn "invalid: \{show e}"
  printLn (lookup "a" j)                  -- Just [1.0,2.5,null]: Show JSON
  printLn (lookup "b" j >>= lookup "c")   -- Just true
  putStrLn (encodeText (JObject [("ok", JBoolean True), ("n", JNumber 3)]))
  putStrLn (format 2 j)                   -- indented
  let m : SortedMap String Int = fromList [("x", 1), ("y", 2)]
  putStrLn (toJSONText m)                 -- {"x":1,"y":2}
```

## `Deriving.Eq`, `Ord`, `DecEq`, `Show`, `Functor`, `Foldable`, `Traversable` (base)

`%runElab derive` builds the implementation; the type of the hint says which.
For a parameterised type, add the constraints the fields need. Functor,
Foldable and Traversable come in that order, as each uses the previous one.

```idris
data Tree a = Leaf | Node (Tree a) a (Tree a)

%hint treeShow : Show a => Show (Tree a)
treeShow = %runElab derive
%hint treeFunctor : Functor Tree
treeFunctor = %runElab derive
%hint treeFoldable : Foldable Tree
treeFoldable = %runElab derive
%hint treeTraversable : Traversable Tree
treeTraversable = %runElab derive

exDeriving : IO ()
exDeriving = do
  let t : Tree Int = Node (Node Leaf 1 Leaf) 2 (Node Leaf 3 Leaf)
  printLn (map (* 10) t)                  -- Node (Node Leaf 10 Leaf) 20 ...
  printLn (sum t, foldMap (\x => the (List Int) [x]) t)  -- (6, [1, 2, 3])
  printLn (toList t)                      -- [3, 2, 1]: reversed, see below
  ignore (traverse printLn t)             -- 1, 2, 3
```

A derived `Foldable` defines `foldMap`, and its `foldr`, `foldl` and `toList`
come out **in reverse order** (the default `foldr` goes through
`Data.Morphisms.Endo`, whose `<+>` composes the other way round). `foldMap`,
`sum`, `traverse` and `for_` are in order. When the order matters, write
`foldr` in the implementation by hand, or use `foldMap (\x => [x])`.

`Deriving.Eq`, `Deriving.Ord` and `Deriving.DecEq` are this fork's, and newer
than some builds of it: if `:module Deriving.Eq` fails, write the
implementations by hand. Values are compared constructor first (in the order
of declaration, for `Ord`), then field by field from left to right. Erased
fields (`0 n : Nat`) are skipped by `Eq` and `Ord`, and make `DecEq` fail. An
indexed family works when its constructors' indices are constructors and
variables (`V (S n)`); otherwise the derivation fails and names the
constructor. A field that holds the type inside another type (`List (T a)`)
needs the implementation to be a `%hint`, as all of these are.

```idris
data Shape = Circle Double | Rect Double Double | Dot

record Pt where
  constructor MkPt
  x : Int
  y : Int

%hint shapeEq : Eq Shape
shapeEq = %runElab derive
%hint shapeOrd : Ord Shape
shapeOrd = %runElab derive
%hint shapeShow : Show Shape
shapeShow = %runElab derive
%hint ptEq : Eq Pt
ptEq = %runElab derive
%hint ptOrd : Ord Pt
ptOrd = %runElab derive
%hint ptShow : Show Pt
ptShow = %runElab derive
%hint ptDecEq : DecEq Pt
ptDecEq = %runElab derive

-- An indexed family with constructor indices
data V : Nat -> Type where
  VNil : V Z
  VCons : Int -> V n -> V (S n)

%hint vEq : Eq (V n)
vEq = %runElab derive

record Sized where
  constructor MkSized
  0 n : Nat
  v : Int

%hint sizedEq : Eq Sized          -- the erased n is not compared
sizedEq = %runElab derive

failing "has an erased field, whose value cannot be compared"
  %hint sizedDecEq : DecEq Sized
  sizedDecEq = %runElab derive

exEqOrd : IO ()
exEqOrd = do
  printLn (Circle 1 == Circle 1, Rect 1 2 < Dot)     -- (True, True)
  printLn (compare (Circle 2) (Circle 1))            -- GT
  printLn (sort [MkPt 2 1, MkPt 1 5, MkPt 1 2])      -- [MkPt 1 2, MkPt 1 5, MkPt 2 1]
  printLn (MkSized 1 3 == MkSized 2 3)               -- True
  printLn (VCons 1 VNil == VCons 1 VNil)             -- True
  case decEq (MkPt 1 2) (MkPt 1 2) of
    Yes prf => putStrLn "equal, with a proof"
    No _ => putStrLn "different"
```

There is no `deriving` clause on `data`.
