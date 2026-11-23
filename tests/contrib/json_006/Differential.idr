-- Generated documents: the old parser (Language.JSON.Lexer and
-- Language.JSON.Parser, over characters) and the byte parser agree on the
-- text that `show` writes and on the text that `format` writes, and the
-- encoder's text parses back to the same value.
import Data.Bits
import Data.ByteString
import Data.List
import Data.String
import Language.JSON
import Language.JSON.Encode
import Language.JSON.Lexer
import Language.JSON.Parser

-- A linear congruential generator (64 bits, wrapping).
next : Bits64 -> Bits64
next s = s * 6364136223846793005 + 1442695040888963407

-- A number in [0, n) from a state.
pick : Bits64 -> Nat -> Nat
pick s n = fromInteger (cast (shiftR s 33) `mod` natToInteger n)

-- The characters of the strings: ASCII (quotes, backslashes and control
-- characters included), and some beyond it.  (Not U+007F..U+009F, which the
-- old parser rejects unescaped, nor characters above U+FFFF, which `show`
-- writes as one truncated `\u` escape.)
chars : List Char
chars = map chr ([0, 1, 8, 9, 10, 12, 13, 31, 32, 34, 47, 92, 126] ++ [48 .. 57] ++ [65 .. 70]
                 ++ [97 .. 122] ++ [0xA0, 0xE9, 0x3B1, 0x7FF, 0x800, 0x20AC, 0xD7FF, 0xE000, 0xFFFD])

charAt : Nat -> Char
charAt i = case drop i chars of
  (c :: _) => c
  [] => 'x'

genString : Nat -> Bits64 -> (String, Bits64)
genString len s = go len s []
  where
    go : Nat -> Bits64 -> List Char -> (String, Bits64)
    go Z s acc = (pack acc, s)
    go (S k) s acc = let s' = next s in go k s' (charAt (pick s' (length chars)) :: acc)

-- Numbers of several shapes: integers (some beyond 2^53), decimals,
-- exponents, negative zero.
genNumber : Bits64 -> (Double, Bits64)
genNumber s =
  let s1 = next s
      s2 = next s1
      m = cast {to = Double} (cast {to = Int} (shiftR s2 20))
  in (case pick s1 8 of
        0 => cast (pick s2 1000)
        1 => negate (cast (pick s2 100000))
        2 => m
        3 => m / 1000.0
        4 => cast (pick s2 100000) / 64.0
        5 => m * 1.0e-12
        6 => m * 1.0e30
        _ => if pick s2 2 == 0 then -0.0 else 0.5, s2)

mutual
  genValue : Nat -> Bits64 -> (JSON, Bits64)
  genValue Z s = genScalar s
  genValue (S d) s =
    let s1 = next s in
    case pick s1 4 of
      0 => let (n, s2) = (pick (next s1) 7, next s1) in
           let (xs, s3) = genList d n s2 [] in (JArray xs, s3)
      1 => let (n, s2) = (pick (next s1) 7, next s1) in
           let (ms, s3) = genMembers d n s2 [] in (JObject ms, s3)
      _ => genScalar s1

  genScalar : Bits64 -> (JSON, Bits64)
  genScalar s =
    let s1 = next s in
    case pick s1 6 of
      0 => (JNull, s1)
      1 => (JBoolean (pick (next s1) 2 == 0), next s1)
      2 => let (x, s2) = genNumber s1 in (JNumber x, s2)
      3 => let (x, s2) = genNumber s1 in (JNumber x, s2)
      _ => let (str, s2) = genString (pick (next s1) 12) (next s1) in (JString str, s2)

  genList : Nat -> Nat -> Bits64 -> List JSON -> (List JSON, Bits64)
  genList d Z s acc = (reverse acc, s)
  genList d (S k) s acc = let (v, s') = genValue d s in genList d k s' (v :: acc)

  genMembers : Nat -> Nat -> Bits64 -> List (String, JSON) -> (List (String, JSON), Bits64)
  genMembers d Z s acc = (reverse acc, s)
  genMembers d (S k) s acc =
    let (key, s1) = genString (pick (next s) 6) (next s)
        (v, s2) = genValue d s1
    in genMembers d k s2 ((key, v) :: acc)

docs : Nat -> Bits64 -> List JSON -> List JSON
docs Z _ acc = reverse acc
docs (S k) s acc = let (v, s') = genValue 5 s in docs k (next s') (v :: acc)

oldParse : String -> Maybe JSON
oldParse s = lexJSON s >>= parseJSON

newParse : String -> Maybe JSON
newParse s = either (const Nothing) Just (parseEither s)

-- Equal, with the order of the members of objects (and duplicate keys) kept.
same : JSON -> JSON -> Bool
same (JArray xs) (JArray ys) = assert_total (length xs == length ys && and (zipWith (\x, y => delay (same x y)) xs ys))
same (JObject xs) (JObject ys) =
  assert_total (length xs == length ys && and (zipWith (\(k, x), (l, y) => delay (k == l && same x y)) xs ys))
same x y = x == y

main : IO ()
main = do
  let ds = docs 400 2026 []
  let texts : List String = map show ds ++ map (format 2) ds
  let disagree = filter (\t => not (maybe False id [| same (oldParse t) (newParse t) |])) texts
  putStrLn ("documents: " ++ show (length ds) ++ ", texts: " ++ show (length texts))
  putStrLn ("old and new parsers disagree on " ++ show (length disagree))
  traverse_ (\t => putStrLn ("  " ++ t)) (take 3 disagree)
  let bad = filter (\d => not (maybe False (same d) (either (const Nothing) Just (parseByteString (encode d))))) ds
  putStrLn ("parse (encode x) /= x for " ++ show (length bad))
  traverse_ (\d => putStrLn ("  " ++ show d ++ "\n  " ++ encodeText d)) (take 3 bad)
  let nbytes = sum (map (\d => length (encode d)) ds)
  putStrLn ("bytes encoded: " ++ show nbytes)
  -- The texts of the encoder for some values
  traverse_ (putStrLn . encodeText)
    [ JArray (map JNumber [0, -0.0, 1, -1, 0.1, 0.5, 1.5e-7, 1.0e21, 123456.789, 9007199254740992, 1.0e300, 5.0e-324, 2.5e-6, 1.0e-6, 0.3, 1.0/0.0, 0.0/0.0])
    , JString "quote \" backslash \\ slash / controls \0\1\b\t\n\f\r\31 del \DEL caf\233 \128512"
    , JObject [("", JNull), ("k\"ey", JArray []), ("b", JObject [])] ]
