-- Accept/reject cases of the byte parser (RFC 8259), and the positions of
-- errors.
import Data.ByteString
import Data.List
import Data.String
import Language.JSON
import Language.JSON.Encode

-- (`\u` escapes and raw bytes are written in the Idris literals; the
-- invalid UTF-8 cases are made of bytes, see `invalidUtf8`)
accepted : List String
accepted =
  [ "null", "true", "false", "0", "-0", "1", "-1", "123", "1.5", "-1.5e10", "1E5", "1e+5", "1e-5"
  , "0.0", "0e0", "1.25E-2", "\"\"", "\"abc\"", "\" \\\" \\\\ \\/ \\b \\f \\n \\r \\t \""
  , "\"\\u0041\\u00e9\\u00E9\\u20ac\"", "\"\\ud83d\\ude00\"", "\"\\uD83D\\uDE00\"", "\"caf\233 \128512\""
  , "\"\DEL\"", "[]", "[1]", "[1,2,3]", "{}", "{\"a\":1}", "{\"a\":1,\"a\":2}"
  , " \t\r\n[ 1 , { \"k\" : [ ] } ]\n ", "[[[[[]]]]]", "1e400", "-1e400", "123456789012345678901234567890"
  ]

rejected : List String
rejected =
  [ "", " ", "nul", "nulll", "True", "[1,]", "[1,,2]", "[,1]", "{\"a\":1,}", "{,}", "{\"a\"}", "{\"a\" 1}"
  , "{1:2}", "{'a':1}", "[1 2]", "01", "-01", "00", "1.", ".5", "-", "+1", "1e", "1e+", "--1", "0x10"
  , "NaN", "Infinity", "\"abc", "\"\\x\"", "\"\\u12\"", "\"\\u12G4\"", "\"\\ud800\"", "\"\\udc00\""
  , "\"\\ud800\\u0041\"", "\"\\ud800x\"", "\"a\tb\"", "\"a\nb\"", "\"\NUL\"", "[1] [2]", "1 2"
  , "\"a\" x", "[", "[1", "{\"a\":", "\f1", "\v1", "\160 1", "\65279 1", "[1]\f"
  ]

-- Byte sequences that are not UTF-8, inside a string.
invalidUtf8 : List (List Bits8)
invalidUtf8 =
  [ [0x80], [0xC0, 0x80], [0xC1, 0xBF], [0xE0, 0x80, 0x80], [0xED, 0xA0, 0x80], [0xF0, 0x80, 0x80, 0x80]
  , [0xF4, 0x90, 0x80, 0x80], [0xF5, 0x80, 0x80, 0x80], [0xFF], [0xC3], [0xE2, 0x82], [0xC3, 0x28] ]

quoted : List Bits8 -> ByteString
quoted bs = pack ([34, 97] ++ bs ++ [98, 34])

check : String -> Bool -> IO ()
check s want = do
  let ok = either (const False) (const True) (parseEither s)
  when (ok /= want) $
    putStrLn ((if want then "wrongly rejected: " else "wrongly accepted: ") ++ show s
              ++ either (\e => " (" ++ show e ++ ")") (\j => " (" ++ show j ++ ")") (parseEither s))

-- The error of a malformed input, with its line and column.
position : String -> IO ()
position s = do
  let bs = fromString s
  putStrLn (show s ++ "\n  " ++ either (showErrorIn bs) (\j => "accepted: " ++ show j) (parseByteString bs))

main : IO ()
main = do
  traverse_ (\s => check s True) accepted
  traverse_ (\s => check s False) rejected
  for_ invalidUtf8 $ \bs =>
    case parseByteString (quoted bs) of
      Left e => putStrLn (show (map toHex (Just (pack bs))) ++ ": " ++ show e)
      Right _ => putStrLn ("wrongly accepted " ++ show bs)
  putStrLn (show (length accepted) ++ " accepted, " ++ show (length rejected) ++ " rejected")
  -- Values
  printLn (parseEither "\"\\u0041\\u00e9\\ud83d\\ude00\"" == Right (JString "A\233\128512"))
  printLn (parseEither "{\"a\":1,\"a\":2,\"b\":[]}")
  printLn (map (\j => case j of JObject ms => map fst ms; _ => []) (parseEither "{\"b\":1,\"a\":2,\"b\":3}"))
  printLn (parseEither "[-0, 0.1, 1e21, 1e400, 9007199254740993, 1.7976931348623157e308, 5e-324, 2.2250738585072014e-308]")
  -- Error positions: offset, line and column
  traverse_ position
    [ "[1, 2,]", "{\"a\": tru}", "[1,\n 2,\n 3 4]", "\"\\ud800\" ", "{\"k\":\n\t\"v\\q\"}"
    , "[\"caf\233\", \"\128512\", x]", "  01", "[1.e5]", "{\"a\" 1}", "[\"a\tb\"]", "\"open", "[1] 2", "[[[" ]
