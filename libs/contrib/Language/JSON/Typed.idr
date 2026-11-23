||| Converting Idris values to and from JSON.
|||
||| ```idris
||| import Language.JSON.Typed
|||
||| record Point where
|||   constructor MkPoint
|||   x, y : Double
|||
||| ToJSON Point where
|||   toJSON p = JObject [("x", toJSON p.x), ("y", toJSON p.y)]
|||
||| FromJSON Point where
|||   fromJSON = withObject "Point" $ \o => [| MkPoint (field o "x") (field o "y") |]
||| ```
|||
||| `Language.JSON.Derive` writes such instances for records and sum types.
|||
||| The instances of this module encode
|||
|||  * `()` as `null`; `Bool`, `String` and `Double` as themselves; a `Char`
|||    as a string of one character;
|||  * the integer types (`Int`, `Integer`, `Nat`, `Bits8`..`Bits64`,
|||    `Int8`..`Int64`) as numbers.  As a JSON number is a `Double` here
|||    (see `Language.JSON.Parse`), an integer of magnitude above 2^53
|||    loses precision both ways; decoding checks that the number is an
|||    integer and in the range of the type;
|||  * `Maybe a` as `null` for `Nothing` and as the value of `a` for `Just`
|||    (so `Just Nothing` and `Nothing` of a `Maybe (Maybe a)` are both
|||    `null`); a `Maybe` member of an object that is missing decodes as
|||    `Nothing`;
|||  * `List`, `SnocList`, `List1` and `Vect n` as arrays (decoding a
|||    `List1` needs a non-empty one, a `Vect n` one of length `n`);
|||  * a pair `(a, b)` as the array `[a, b]`, so a triple `(a, b, c)`, which
|||    is `(a, (b, c))`, is `[a, [b, c]]`;
|||  * `Either a b` as `{"Left": a}` or `{"Right": b}`;
|||  * `SortedMap String v` and `HashMap String v` as objects (a key that is
|||    there twice takes the last value);
|||  * `JSON` as itself.
module Language.JSON.Typed

import Data.ByteString
import public Data.ByteString.Builder
import Data.HashMap
import Data.List
import Data.List1
import Data.SnocList
import Data.SortedMap
import Data.String
import Data.Vect

import public Language.JSON.Data
import public Language.JSON.Encode
import public Language.JSON.Parse

%default total

------------------------------------------------------------------------
-- Errors
------------------------------------------------------------------------

||| A step from a JSON value into one of its parts.
public export
data PathElem : Type where
  ||| The member of an object with this key.
  Key : String -> PathElem
  ||| The element of an array at this index (from 0).
  Index : Nat -> PathElem

||| Same step.
export
Eq PathElem where
  Key a == Key b = a == b
  Index a == Index b = a == b
  _ == _ = False

||| Why a value could not be decoded.
public export
data DecodeError : Type where
  ||| The input is not JSON.
  Syntax : JSONError -> DecodeError
  ||| The JSON value does not have the expected shape.  The path leads from
  ||| the whole value to the part that does not fit.
  Mismatch : (path : List PathElem) -> (message : String) -> DecodeError

||| Same error.
export
Eq DecodeError where
  Syntax a == Syntax b = a == b
  Mismatch p m == Mismatch q n = p == q && m == n
  _ == _ = False

-- A key as a step of a path: `.key` if it is a simple name, and as a
-- quoted string in brackets otherwise.
showKey : String -> String
showKey k =
  if k /= "" && all (\c => isAlphaNum c || c == '_') (unpack k)
     then "." ++ k
     else "[" ++ encodeText (JString k) ++ "]"

||| The path to a part of a value, in the notation of JSONPath (`$` is the
||| whole value): `$.users[3].name`.
export
showPath : List PathElem -> String
showPath ps = "$" ++ concatMap step ps
  where
    step : PathElem -> String
    step (Key k) = showKey k
    step (Index i) = "[" ++ show i ++ "]"

||| `invalid JSON at byte <offset>: <reason>`, or
||| `at <path>: <message>`.
export
Show DecodeError where
  show (Syntax e) = "invalid JSON at " ++ show e
  show (Mismatch p m) = "at " ++ showPath p ++ ": " ++ m

||| Fail with a message about the value being decoded.
export
failDecode : String -> Either DecodeError a
failDecode msg = Left (Mismatch [] msg)

||| Put a step in front of the path of an error, for an error in a member of
||| an object.
export
inKey : String -> Either DecodeError a -> Either DecodeError a
inKey k (Left (Mismatch p m)) = Left (Mismatch (Key k :: p) m)
inKey _ r = r

||| Put a step in front of the path of an error, for an error in an element
||| of an array.
export
inIndex : Nat -> Either DecodeError a -> Either DecodeError a
inIndex i (Left (Mismatch p m)) = Left (Mismatch (Index i :: p) m)
inIndex _ r = r

||| What kind of value this is, for error messages: `null`, `a boolean`,
||| `a number`, `a string`, `an array` or `an object`.
export
describe : JSON -> String
describe JNull = "null"
describe (JBoolean _) = "a boolean"
describe (JNumber _) = "a number"
describe (JString _) = "a string"
describe (JArray _) = "an array"
describe (JObject _) = "an object"

||| Fail because the value is not what was expected:
||| `expected <what>, got <describe value>`.
export
unexpected : (what : String) -> JSON -> Either DecodeError a
unexpected what j = failDecode ("expected " ++ what ++ ", got " ++ describe j)

------------------------------------------------------------------------
-- The interfaces
------------------------------------------------------------------------

||| Types whose values can be written as JSON.
public export
interface ToJSON a where
  constructor MkToJSON
  ||| The JSON value.
  toJSON : a -> JSON
  ||| The compact JSON text, as `encodeBuilder (toJSON x)` (the default)
  ||| does.  An instance may write it directly, without building the `JSON`
  ||| value first.
  toEncoding : a -> Builder
  toEncoding x = encodeBuilder (toJSON x)
  ||| A writer of the compact JSON text, as `writeValue (toJSON x)` (the
  ||| default) is.  An instance may write it directly, without building the
  ||| `JSON` value first (the derived instances of records do).
  toWriter : a -> JSONWriter
  toWriter x = writeValue (toJSON x)

||| Types whose values can be read from JSON.
public export
interface FromJSON a where
  constructor MkFromJSON
  ||| The value, or why the JSON value does not stand for one.
  fromJSON : JSON -> Either DecodeError a
  ||| The value of a member of an object that is missing, if a missing
  ||| member is allowed; `Nothing` (the default) if it is an error.  The
  ||| instance for `Maybe` has `Just Nothing`.
  fromMissing : Maybe a
  fromMissing = Nothing
  ||| Decode a value from the JSON text at `pos` in an input (after
  ||| whitespace), without building a `JSON`
  ||| value if the instance can: the value and the position after its text,
  ||| or `StepFail`.  It must give the value that `fromJSON` gives for the
  ||| JSON value of the text, or fail; `fromJSONBytes` uses it, and on a
  ||| failure decodes the input again with `fromJSON`, which says why.  The
  ||| default parses a `JSON` value and gives it to `fromJSON`.
  fromJSONAt : Input -> (pos : Int) -> Step a
  fromJSONAt b p = case valueAt b p of
    StepOk j q => case fromJSON j of
                    Right x => StepOk x q
                    Left _ => StepFail
    StepFail => StepFail

------------------------------------------------------------------------
-- Helpers for writing instances
------------------------------------------------------------------------

||| Decode an object with a function of its members, or fail with
||| `expected <name>`.
export
withObject : (name : String) -> (List (String, JSON) -> Either DecodeError a) ->
             JSON -> Either DecodeError a
withObject _ f (JObject ms) = f ms
withObject name _ j = unexpected (name ++ " (an object)") j

||| Decode an array with a function of its elements.
export
withArray : (name : String) -> (List JSON -> Either DecodeError a) ->
            JSON -> Either DecodeError a
withArray _ f (JArray xs) = f xs
withArray name _ j = unexpected (name ++ " (an array)") j

||| Decode a string with a function of it.
export
withString : (name : String) -> (String -> Either DecodeError a) ->
             JSON -> Either DecodeError a
withString _ f (JString s) = f s
withString name _ j = unexpected (name ++ " (a string)") j

||| Decode a number with a function of it.
export
withNumber : (name : String) -> (Double -> Either DecodeError a) ->
             JSON -> Either DecodeError a
withNumber _ f (JNumber x) = f x
withNumber name _ j = unexpected (name ++ " (a number)") j

||| The member of an object with this key (the first one if there are
||| several), decoded; if there is none, the `fromMissing` value of the type
||| or an error `missing member`.  An error in the member has the key in its
||| path.
export
field : FromJSON a => List (String, JSON) -> String -> Either DecodeError a
field ms k = case lookup k ms of
  Just v => inKey k (fromJSON v)
  Nothing => case fromMissing of
               Just x => Right x
               Nothing => Left (Mismatch [Key k] "missing member")

||| The member of an object with this key, decoded, or `Nothing` if there
||| is none or it is `null`.
export
optionalField : FromJSON a => List (String, JSON) -> String -> Either DecodeError (Maybe a)
optionalField ms k = case lookup k ms of
  Nothing => Right Nothing
  Just JNull => Right Nothing
  Just v => map Just (inKey k (fromJSON v))

||| Decode the elements of an array, with their indices in the paths of the
||| errors.  Does not use stack in proportion to the length.
export
decodeElements : FromJSON a => List JSON -> Either DecodeError (List a)
decodeElements xs = go 0 xs [<]
  where
    go : Nat -> List JSON -> SnocList a -> Either DecodeError (List a)
    go _ [] acc = Right (acc <>> [])
    go i (y :: ys) acc = case inIndex i (fromJSON y) of
      Left e => Left e
      Right v => go (S i) ys (acc :< v)

------------------------------------------------------------------------
-- Entry points
------------------------------------------------------------------------

||| The compact JSON text of a value, as UTF-8 bytes (`toEncoding`).
export
toJSONBytes : ToJSON a => a -> ByteString
toJSONBytes x = runWriter (toWriter x)

||| The compact JSON text of a value, as a string.
export
toJSONText : ToJSON a => a -> String
toJSONText x = encodeText (toJSON x)

||| Parse JSON bytes (with the given limits) and decode a value from them.
|||
||| The value is decoded from the bytes with `fromJSONAt`; if that fails,
||| the bytes are parsed into a `JSON` value and decoded with `fromJSON`,
||| which gives the error.
export
fromJSONBytesWith : FromJSON a => ParseOptions -> ByteString -> Either DecodeError a
fromJSONBytesWith opts bs =
  let (inp, off) = inputOf (cast opts.maxDepth) bs in
  case fromJSONAt inp (skipWsAt inp off) of
       StepOk x p => if atEnd inp (skipWsAt inp p) then Right x else viaTree
       StepFail => viaTree
  where
    viaTree : Either DecodeError a
    viaTree = case parseBytesWith opts bs of
      Left e => Left (Syntax e)
      Right j => fromJSON j

||| Parse JSON bytes and decode a value from them.
export
fromJSONBytes : FromJSON a => ByteString -> Either DecodeError a
fromJSONBytes = fromJSONBytesWith defaultParseOptions

||| Parse a JSON text and decode a value from it.
export
fromJSONText : FromJSON a => String -> Either DecodeError a
fromJSONText s = fromJSONBytes (fromString s)

------------------------------------------------------------------------
-- Instances
------------------------------------------------------------------------

export
ToJSON JSON where
  toJSON = id
  toEncoding = encodeBuilder

export
FromJSON JSON where
  fromJSON = Right

export
ToJSON () where
  toJSON () = JNull

export
FromJSON () where
  fromJSON JNull = Right ()
  fromJSON j = unexpected "null" j

export
ToJSON Bool where
  toJSON = JBoolean
  toWriter = writeBool

export
FromJSON Bool where
  fromJSON (JBoolean b) = Right b
  fromJSON j = unexpected "a boolean" j
  fromJSONAt b p = case boolAt b p of
    1 => StepOk True (p + 4)
    0 => StepOk False (p + 5)
    _ => StepFail

export
ToJSON String where
  toJSON = JString
  toWriter = writeString

export
FromJSON String where
  fromJSON (JString s) = Right s
  fromJSON j = unexpected "a string" j
  fromJSONAt b p = stringAt b p

export
ToJSON Char where
  toJSON c = JString (cast c)

export
FromJSON Char where
  fromJSON (JString s) = case unpack s of
    [c] => Right c
    _ => failDecode "expected a string of one character"
  fromJSON j = unexpected "a string of one character" j

export
ToJSON Double where
  toJSON = JNumber
  toWriter = writeNumber

export
FromJSON Double where
  fromJSON (JNumber x) = Right x
  fromJSON j = unexpected "a number" j
  fromJSONAt b p = numberAt b p StepOk

-- An integer number in `[lo, hi)`, which are exact doubles.
integral : (name : String) -> (lo, hi : Double) -> JSON -> Either DecodeError Double
integral name lo hi (JNumber x) =
  if floor x /= x || x /= x then failDecode ("expected an integer (" ++ name ++ "), got " ++ encodeText (JNumber x))
  else if x < lo || x >= hi then failDecode ("number out of the range of " ++ name ++ ": " ++ encodeText (JNumber x))
  else Right x
integral name _ _ j = unexpected ("an integer (" ++ name ++ ")") j

export
ToJSON Int where
  toJSON i = JNumber (cast i)
  toWriter = writeInt

export
FromJSON Int where
  fromJSON j = map cast (integral "Int" (-9223372036854775808.0) 9223372036854775808.0 j)
  -- (the checks of `integral`)
  fromJSONAt b p = numberAt b p $ \x, q =>
    if floor x /= x || x /= x || x < -9223372036854775808.0 || x >= 9223372036854775808.0
       then StepFail else StepOk (cast x) q

export
ToJSON Integer where
  toJSON i = JNumber (cast i)

-- 2^1024, above every finite double.
infinity : Double
infinity = 1.0 / 0.0

export
FromJSON Integer where
  fromJSON j = map cast (integral "Integer" (negate infinity) infinity j)

export
ToJSON Nat where
  toJSON n = JNumber (cast n)

export
FromJSON Nat where
  fromJSON j = map (\x => fromInteger (cast x)) (integral "Nat" 0.0 infinity j)

export
ToJSON Bits8 where
  toJSON i = JNumber (cast i)

export
FromJSON Bits8 where
  fromJSON j = map (\x => cast {to = Bits8} (cast {to = Int} x)) (integral "Bits8" 0.0 256.0 j)

export
ToJSON Bits16 where
  toJSON i = JNumber (cast i)

export
FromJSON Bits16 where
  fromJSON j = map (\x => cast {to = Bits16} (cast {to = Int} x)) (integral "Bits16" 0.0 65536.0 j)

export
ToJSON Bits32 where
  toJSON i = JNumber (cast i)

export
FromJSON Bits32 where
  fromJSON j = map (\x => cast {to = Bits32} (cast {to = Integer} x)) (integral "Bits32" 0.0 4294967296.0 j)

export
ToJSON Bits64 where
  toJSON i = JNumber (cast i)

export
FromJSON Bits64 where
  fromJSON j = map (\x => cast {to = Bits64} (cast {to = Integer} x)) (integral "Bits64" 0.0 18446744073709551616.0 j)

export
ToJSON Int8 where
  toJSON i = JNumber (cast i)

export
FromJSON Int8 where
  fromJSON j = map (\x => cast {to = Int8} (cast {to = Int} x)) (integral "Int8" (-128.0) 128.0 j)

export
ToJSON Int16 where
  toJSON i = JNumber (cast i)

export
FromJSON Int16 where
  fromJSON j = map (\x => cast {to = Int16} (cast {to = Int} x)) (integral "Int16" (-32768.0) 32768.0 j)

export
ToJSON Int32 where
  toJSON i = JNumber (cast i)

export
FromJSON Int32 where
  fromJSON j = map (\x => cast {to = Int32} (cast {to = Integer} x)) (integral "Int32" (-2147483648.0) 2147483648.0 j)

export
ToJSON Int64 where
  toJSON i = JNumber (cast i)

export
FromJSON Int64 where
  fromJSON j = map (\x => cast {to = Int64} (cast {to = Integer} x))
                   (integral "Int64" (-9223372036854775808.0) 9223372036854775808.0 j)

export
ToJSON a => ToJSON (Maybe a) where
  toJSON Nothing = JNull
  toJSON (Just x) = toJSON x
  toWriter Nothing = writeRaw "null"
  toWriter (Just x) = toWriter x

export
FromJSON a => FromJSON (Maybe a) where
  fromJSON JNull = Right Nothing
  fromJSON j = map Just (fromJSON j)
  fromMissing = Just Nothing
  fromJSONAt b p =
    if nullAt b p then StepOk Nothing (p + 4)
    else case fromJSONAt b p of
           StepOk x q => StepOk (Just x) q
           StepFail => StepFail

-- Write the elements of a list after the first, each after a comma.
writeRest : (a -> JSONWriter) -> List a -> JSONWriter
writeRest wr [] o p w = MkIORes p w
writeRest wr (x :: xs) o p w =
  case writeByte 44 o p w of
    MkIORes p w => case wr x o p w of
      MkIORes p w => writeRest wr xs o p w

-- Write a list as an array.
writeList : (a -> JSONWriter) -> List a -> JSONWriter
writeList wr [] o p w = writeRaw "[]" o p w
writeList wr (x :: xs) o p w =
  case writeByte 91 o p w of
    MkIORes p w => case wr x o p w of
      MkIORes p w => case writeRest wr xs o p w of
        MkIORes p w => writeByte 93 o p w

-- The elements of an array from `p` (after whitespace, at an element),
-- in reverse order so far.
covering
elementsAt : FromJSON a => Input -> (pos : Int) -> List a -> Step (List a)
elementsAt b p acc = case fromJSONAt b p of
  StepFail => StepFail
  StepOk x q =>
    let j = skipWsAt b q
        c = byteAtOr0 b j in
    if c == 93 then StepOk (reverse (x :: acc)) (j + 1)
    else if c == 44
      then let k = skipWsAt b (j + 1) in
           if byteAtOr0 b k == 93 then StepFail else elementsAt b k (x :: acc)
    else StepFail

export
ToJSON a => ToJSON (List a) where
  toJSON xs = JArray (map toJSON xs)
  toWriter xs = writeList toWriter xs

export
FromJSON a => FromJSON (List a) where
  fromJSON = withArray "a list" decodeElements
  fromJSONAt b p =
    if byteAtOr0 b p /= 91 then StepFail else
    case enter b of
      Nothing => StepFail
      Just inner =>
        let j = skipWsAt b (p + 1) in
        if byteAtOr0 b j == 93 then StepOk [] (j + 1)
        else assert_total (elementsAt inner j [])

export
ToJSON a => ToJSON (SnocList a) where
  toJSON xs = JArray (map toJSON (xs <>> []))

export
FromJSON a => FromJSON (SnocList a) where
  fromJSON = withArray "a list" (map ([<] <><) . decodeElements)

export
ToJSON a => ToJSON (List1 a) where
  toJSON xs = JArray (map toJSON (forget xs))

export
FromJSON a => FromJSON (List1 a) where
  fromJSON = withArray "a non-empty list" $ \xs => case xs of
    [] => failDecode "expected a non-empty array, got an empty one"
    _ => do ys <- decodeElements xs
            case ys of
              (y :: ys) => Right (y ::: ys)
              [] => failDecode "expected a non-empty array, got an empty one"

export
ToJSON a => ToJSON (Vect n a) where
  toJSON xs = JArray (map toJSON (toList xs))

export
{n : Nat} -> FromJSON a => FromJSON (Vect n a) where
  fromJSON = withArray "a vector" $ \xs => do
    ys <- decodeElements xs
    case toVect n ys of
      Just v => Right v
      Nothing => failDecode ("expected an array of length " ++ show n ++ ", got one of length " ++ show (length ys))

export
(ToJSON a, ToJSON b) => ToJSON (a, b) where
  toJSON (x, y) = JArray [toJSON x, toJSON y]

export
(FromJSON a, FromJSON b) => FromJSON (a, b) where
  fromJSON (JArray [x, y]) = [| (inIndex 0 (fromJSON x), inIndex 1 (fromJSON y)) |]
  fromJSON (JArray xs) = failDecode ("expected an array of length 2, got one of length " ++ show (length xs))
  fromJSON j = unexpected "a pair (an array of length 2)" j

export
(ToJSON a, ToJSON b) => ToJSON (Either a b) where
  toJSON (Left x) = JObject [("Left", toJSON x)]
  toJSON (Right y) = JObject [("Right", toJSON y)]

export
(FromJSON a, FromJSON b) => FromJSON (Either a b) where
  fromJSON (JObject [("Left", x)]) = map Left (inKey "Left" (fromJSON x))
  fromJSON (JObject [("Right", y)]) = map Right (inKey "Right" (fromJSON y))
  fromJSON j = unexpected "{\"Left\": ...} or {\"Right\": ...}" j

-- Decode the values of the members of an object, with the keys in the paths
-- of the errors; in the order of the members.
decodeMembers : FromJSON v => List (String, JSON) -> Either DecodeError (List (String, v))
decodeMembers ms = go ms [<]
  where
    go : List (String, JSON) -> SnocList (String, v) -> Either DecodeError (List (String, v))
    go [] acc = Right (acc <>> [])
    go ((k, j) :: rest) acc = case inKey k (fromJSON j) of
      Left e => Left e
      Right x => go rest (acc :< (k, x))

export
ToJSON v => ToJSON (SortedMap String v) where
  toJSON m = JObject (map (\(k, x) => (k, toJSON x)) (SortedMap.toList m))

export
FromJSON v => FromJSON (SortedMap String v) where
  fromJSON = withObject "a map" (map SortedMap.fromList . decodeMembers)

export
ToJSON v => ToJSON (HashMap String v) where
  toJSON m = JObject (map (\(k, x) => (k, toJSON x)) (HashMap.toList m))

export
FromJSON v => FromJSON (HashMap String v) where
  fromJSON = withObject "a map" (map HashMap.fromList . decodeMembers)
