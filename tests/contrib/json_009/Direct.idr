-- The decoders in place and the writers of derived records (`fromJSONAt`,
-- `toWriter`) against the `JSON` values (`fromJSON`, `toJSON`), which are
-- the reference: on generated values, written in order and also with the
-- members reordered, repeated, missing or extra, with other whitespace,
-- with values of the wrong types, cut short, with trailing bytes, and
-- nested beyond a limit.
import Data.Bits
import Data.ByteString
import Data.List
import Data.String
import Language.JSON
import Language.JSON.Derive
import Language.JSON.Encode
import Language.JSON.Typed

%language ElabReflection
%default covering

record Inner where
  constructor MkInner
  label : String
  weight : Double

Eq Inner where
  a == b = a.label == b.label && a.weight == b.weight

Show Inner where
  show a = "MkInner " ++ show a.label ++ " " ++ show a.weight

%hint
innerTo : ToJSON Inner
innerTo = %runElab deriveToJSON defaultOptions

%hint
innerFrom : FromJSON Inner
innerFrom = %runElab deriveFromJSON defaultOptions

record Item where
  constructor MkItem
  id : Int
  name : String
  price : Double
  tags : List String
  active : Bool
  note : Maybe String
  inner : Inner
  more : List Inner

Eq Item where
  a == b = a.id == b.id && a.name == b.name && a.price == b.price && a.tags == b.tags
           && a.active == b.active && a.note == b.note && a.inner == b.inner && a.more == b.more

Show Item where
  show a = "MkItem " ++ show a.id ++ " " ++ show a.name ++ " " ++ show a.price ++ " "
           ++ show a.tags ++ " " ++ show a.active ++ " " ++ show a.note ++ " ("
           ++ show a.inner ++ ") " ++ show a.more

%hint
itemTo : ToJSON Item
itemTo = %runElab deriveToJSON defaultOptions

%hint
itemFrom : FromJSON Item
itemFrom = %runElab deriveFromJSON defaultOptions

-- Keys that are not plain (a quote, a backslash, non-ASCII), renamed.
record Odd where
  constructor MkOdd
  plain : Int
  quoted : Int
  accented : Int

Eq Odd where
  a == b = a.plain == b.plain && a.quoted == b.quoted && a.accented == b.accented

Show Odd where
  show a = "MkOdd " ++ show a.plain ++ " " ++ show a.quoted ++ " " ++ show a.accented

oddName : String -> String
oddName "quoted" = "say \"hi\"\\"
oddName "accented" = "caf\233"
oddName n = n

%hint
oddTo : ToJSON Odd
oddTo = %runElab deriveToJSON ({ fieldName := oddName } defaultOptions)

%hint
oddFrom : FromJSON Odd
oddFrom = %runElab deriveFromJSON ({ fieldName := oddName } defaultOptions)

-- A linear congruential generator.
next : Bits64 -> Bits64
next s = s * 6364136223846793005 + 1442695040888963407

pick : Bits64 -> Nat -> Nat
pick s n = fromInteger (cast (shiftR s 33) `mod` natToInteger n)

chars : List Char
chars = map chr ([0, 9, 10, 31, 32, 34, 47, 92, 126] ++ [48 .. 57] ++ [97 .. 122] ++ [0xE9, 0x20AC, 0x1F600])

genString : Bits64 -> (String, Bits64)
genString s = go (pick s 8) (next s) []
  where
    go : Nat -> Bits64 -> List Char -> (String, Bits64)
    go Z s acc = (pack acc, s)
    go (S k) s acc = go k (next s) ((case drop (pick s (length chars)) chars of (c :: _) => c; [] => 'x') :: acc)

genDouble : Bits64 -> (Double, Bits64)
genDouble s = let s1 = next s in
  (case pick s 4 of
     0 => cast (pick s1 1000)
     1 => cast (pick s1 100000) / 64.0
     2 => negate (cast (pick s1 1000000)) * 1.0e-9
     _ => cast (pick s1 1000) * 1.0e25, next s1)

genInner : Bits64 -> (Inner, Bits64)
genInner s = let (l, s1) = genString s
                 (w, s2) = genDouble s1 in (MkInner l w, s2)

genList : Nat -> (Bits64 -> (a, Bits64)) -> Bits64 -> (List a, Bits64)
genList Z g s = ([], s)
genList (S k) g s = let (x, s1) = g s
                        (xs, s2) = genList k g s1 in (x :: xs, s2)

genItem : Bits64 -> (Item, Bits64)
genItem s =
  let i = cast {to = Int} (pick s 2000000) - 1000000
      (n, s1) = genString (next s)
      (p, s2) = genDouble s1
      (ts, s3) = genList (pick s2 4) genString (next s2)
      a = pick s3 2 == 0
      (nt, s4) = genString (next s3)
      (inn, s5) = genInner s4
      (mo, s6) = genList (pick s5 3) genInner (next s5)
  in (MkItem i n p ts a (if pick s6 3 == 0 then Nothing else Just nt) inn mo, next s6)

-- The text of a JSON value with whitespace between the tokens.
spaced : JSON -> String
spaced (JArray xs) = "[ " ++ joinBy " , " (map spaced xs) ++ " ]"
spaced (JObject ms) = "{\n\t" ++ joinBy " ,\r\n " (map (\(k, v) => encodeText (JString k) ++ " : " ++ spaced v) ms) ++ " }"
spaced j = encodeText j

-- Variants of the members of an object: the same, reversed, the first
-- repeated with another value, the last missing, one more, a value of the
-- wrong type.
variants : JSON -> List JSON
variants (JObject ms@(m :: rest)) =
  [ JObject ms, JObject (reverse ms), JObject (ms ++ [(fst m, JNull)]), JObject ((fst m, JBoolean True) :: ms)
  , JObject (take (length ms `minus` 1) ms), JObject (ms ++ [("extra", JArray [])])
  , JObject (map (\(k, v) => (k, case v of JNumber _ => JString "1"; JString _ => JNumber 1.0; x => x)) ms) ]
variants j = [j]

-- The reference: parse into a `JSON` value, then `fromJSON`.
reference : FromJSON a => ParseOptions -> ByteString -> Either DecodeError a
reference opts bs = case parseBytesWith opts bs of
  Left e => Left (Syntax e)
  Right j => fromJSON j

same : (FromJSON a, Eq a) => ParseOptions -> ByteString -> Bool
same opts bs = fromJSONBytesWith {a} opts bs == reference opts bs

texts : JSON -> List ByteString
texts j = let t = encode j in
  [ t, fromString (spaced j), t <+> fromString " \n", t <+> fromString " x"
  , takeInt' (length t `minus` 1) t, fromString "  " <+> t ]
  where
    takeInt' : Nat -> ByteString -> ByteString
    takeInt' n bs = Data.ByteString.take n bs

check : Nat -> Bits64 -> (Nat, Nat, Nat) -> (Nat, Nat, Nat)
check Z _ acc = acc
check (S k) s (docs, bad, wbad) =
  let (it, s1) = genItem s
      j = toJSON it
      -- the writer writes what the encoder writes of the `JSON` value
      wbad' = if toJSONBytes it == encode j then wbad else wbad + 1
      docsHere = concatMap texts (variants j)
      deep = MkParseOptions (cast (pick s1 4))
      bad' = length (filter (\d => not (same {a = Item} defaultParseOptions d && same {a = Item} deep d)) docsHere)
  in check k s1 (docs + length docsHere, bad + bad', wbad')

main : IO ()
main = do
  let (docs, bad, wbad) = check 300 42 (0, 0, 0)
  putStrLn "\{show docs} documents: \{show bad} decoded differently, \{show wbad} written differently"
  -- a value decoded in place is the same as through `JSON`
  let (it, _) = genItem 7
  printLn (fromJSONBytes {a = Item} (toJSONBytes it) == Right it)
  -- keys that are not plain are found through `JSON`
  let o = MkOdd 1 2 3
  putStrLn (toJSONText o)
  printLn (toJSONBytes o == encode (toJSON o))
  printLn (fromJSONBytes {a = Odd} (toJSONBytes o) == Right o)
  printLn (fromJSONBytes {a = Odd} (fromString "{\"plain\": 1, \"say \\\"hi\\\"\\\\\": 2, \"caf\\u00e9\": 3}") == Right o)
  -- an error is the one of the reference
  printLn (fromJSONBytes {a = Item} (fromString "{\"id\": 1.5}"))
  printLn (fromJSONBytes {a = Item} (fromString "{\"id\": 1, \"name\": \"a\", \"price\": 1, \"tags\": [\"x\",], \"active\": true}"))
