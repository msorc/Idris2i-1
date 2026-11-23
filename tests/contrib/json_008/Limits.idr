-- The nesting limit, and inputs of a few megabytes.
import Data.ByteString
import Data.ByteString.Builder as B
import Data.List
import Language.JSON
import Language.JSON.Encode

nested : Nat -> ByteString
nested n = Data.ByteString.replicate n 91 <+> Data.ByteString.replicate n 93

-- `n` objects with mixed members, as one array, built as bytes.
big : Nat -> ByteString
big n = toByteString ("[" <+> go n neutral <+> "]")
  where
    item : Nat -> Builder
    item i = B.utf8String ("{\"id\":" ++ show i ++ ",\"name\":\"item \\\"" ++ show i
                           ++ "\\\" caf\233\",\"ok\":true,\"xs\":[1.5,-2,300,null],\"o\":{}}")
    go : Nat -> Builder -> Builder
    go Z acc = acc
    go (S k) acc = go k ((if k == 0 then neutral else B.utf8String ",") <+> item k <+> acc)

main : IO ()
main = do
  printLn (map (const ()) (parseByteString (nested 512)))
  printLn (map (const ()) (parseByteString (nested 513)))
  printLn (map (const ()) (parseBytesWith (MkParseOptions 10) (nested 10)))
  printLn (map (const ()) (parseBytesWith (MkParseOptions 10) (nested 11)))
  printLn (map (const ()) (parseBytesWith (MkParseOptions 4) (fromString "[{\"a\":[{\"b\":1}]}]")))
  -- a hostile input: a million open brackets
  printLn (map (const ()) (parseByteString (Data.ByteString.replicate 1000000 91)))
  -- deep nesting within a larger limit
  printLn (map (const ()) (parseBytesWith (MkParseOptions 5000) (nested 5000)))
  let doc = big 40000
  putStrLn ("input bytes: " ++ show (length doc))
  case parseByteString doc of
    Left e => putStrLn (show e)
    Right j@(JArray xs) => do
      putStrLn ("elements: " ++ show (length xs))
      let out = encode j
      putStrLn ("output bytes: " ++ show (length out) ++ ", same: " ++ show (out == doc))
      printLn (parseByteString out == Right j)
    Right _ => putStrLn "not an array"
  -- a long string and a long array of numbers
  let s = Data.ByteString.replicate 3000000 97
  printLn (map (\j => case j of JString x => length x; _ => 0) (parseByteString (Data.ByteString.singleton 34 <+> s <+> Data.ByteString.singleton 34)))
  let nums = JArray (map (\i => JNumber (cast i / 4.0)) [1 .. 200000])
  printLn (map (== nums) (parseByteString (encode nums)))
