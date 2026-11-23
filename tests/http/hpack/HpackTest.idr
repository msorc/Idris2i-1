-- HPACK (RFC 7541): the examples of appendix C byte for byte in both
-- directions, the Huffman code, and the error and limit rules.
import Data.ByteString as BS
import Data.ByteString.Builder
import Data.List
import Data.String
import Network.HTTP2.HPACK
import Network.HTTP2.HPACK.Huffman

%default total

-- The bytes of hexadecimal digits (spaces are ignored).
hex : String -> ByteString
hex s = BS.pack (go (filter (/= ' ') (unpack s)))
  where
    digit : Char -> Bits8
    digit c = if c >= 'a' then cast (ord c - 87) else cast (ord c - 48)
    go : List Char -> List Bits8
    go (a :: b :: rest) = (digit a * 16 + digit b) :: go rest
    go _ = []

f : String -> String -> HeaderField
f n v = field (fromString n) (fromString v)

check : String -> Bool -> String -> IO ()
check name ok detail = putStrLn (name ++ ": " ++ (if ok then "ok" else "FAIL " ++ detail))

showTable : DynamicTable -> List String
showTable t =
  zipWith (\i, e => "  [" ++ show i ++ "] (s=" ++ show (entrySize e.name e.value) ++ ") "
                    ++ toStringLossy e.name ++ ": " ++ toStringLossy e.value)
          [the Int 1 .. tableCount t] (tableEntries t)
  ++ ["  size " ++ show (tableSize t)]

printTable : DynamicTable -> IO ()
printTable t = traverse_ putStrLn (showTable t)

-- Decode a block, compare with the expected list, print the table.
decodeStep : String -> DecoderState -> String -> List HeaderField -> IO DecoderState
decodeStep name st bytes expect =
  case decodeHeaderBlock st (hex bytes) of
    Left e => do check (name ++ " decode") False (show e); pure st
    Right (fs, st') => do
      check (name ++ " decode") (fs == expect) (show fs)
      printTable (decoderTable st')
      pure st'

-- Encode with a choice of representation and compare the bytes.
encodeStep : String -> EncoderState -> (DynamicTable -> HeaderField -> Indexing) ->
             List HeaderField -> String -> IO EncoderState
encodeStep name st choose fs bytes = do
  let (b, st') = encodeHeaderBlockWith choose st fs
      got = toByteString b
  check (name ++ " encode") (got == hex bytes) (toHex got)
  pure st'

defaultChoice : DynamicTable -> HeaderField -> Indexing
defaultChoice t = defaultIndexing (tableMaxSize t)

-- Both directions of a sequence of blocks, with encoder and decoder tables
-- compared after each block.
sequenceTest : String -> Int -> Bool -> List (List HeaderField, String) -> IO ()
sequenceTest name size huff steps = go 1 (newEncoder size huff) (newDecoder size 65536) steps
  where
    go : Int -> EncoderState -> DecoderState -> List (List HeaderField, String) -> IO ()
    go _ _ _ [] = pure ()
    go k enc dec ((fs, bytes) :: rest) = do
      let nm = name ++ "." ++ show k
      enc' <- encodeStep nm enc defaultChoice fs bytes
      dec' <- decodeStep nm dec bytes fs
      check (nm ++ " tables agree")
            (showTable (encoderTable enc') == showTable (decoderTable dec')) ""
      go (k + 1) enc' dec' rest

c3 : List (List HeaderField, String)
c3 =
  [ ([f ":method" "GET", f ":scheme" "http", f ":path" "/", f ":authority" "www.example.com"],
     "8286 8441 0f77 7777 2e65 7861 6d70 6c65 2e63 6f6d")
  , ([f ":method" "GET", f ":scheme" "http", f ":path" "/", f ":authority" "www.example.com",
      f "cache-control" "no-cache"],
     "8286 84be 5808 6e6f 2d63 6163 6865")
  , ([f ":method" "GET", f ":scheme" "https", f ":path" "/index.html",
      f ":authority" "www.example.com", f "custom-key" "custom-value"],
     "8287 85bf 400a 6375 7374 6f6d 2d6b 6579 0c63 7573 746f 6d2d 7661 6c75 65")
  ]

c4 : List (List HeaderField, String)
c4 =
  [ (fst (c3Get 0), "8286 8441 8cf1 e3c2 e5f2 3a6b a0ab 90f4 ff")
  , (fst (c3Get 1), "8286 84be 5886 a8eb 1064 9cbf")
  , (fst (c3Get 2), "8287 85bf 4088 25a8 49e9 5ba9 7d7f 8925 a849 e95b b8e8 b4bf")
  ]
  where
    c3Get : Nat -> (List HeaderField, String)
    c3Get n = case getAt n c3 of
                Just x => x
                Nothing => ([], "")

resp1, resp2, resp3 : List HeaderField
resp1 = [ f ":status" "302", f "cache-control" "private"
        , f "date" "Mon, 21 Oct 2013 20:13:21 GMT", f "location" "https://www.example.com" ]
resp2 = [ f ":status" "307", f "cache-control" "private"
        , f "date" "Mon, 21 Oct 2013 20:13:21 GMT", f "location" "https://www.example.com" ]
resp3 = [ f ":status" "200", f "cache-control" "private"
        , f "date" "Mon, 21 Oct 2013 20:13:22 GMT", f "location" "https://www.example.com"
        , f "content-encoding" "gzip"
        , f "set-cookie" "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1" ]

c5 : List (List HeaderField, String)
c5 =
  [ (resp1, "4803 3330 3258 0770 7269 7661 7465 611d 4d6f 6e2c 2032 3120 4f63 7420 3230 3133 2032 303a 3133 3a32 3120 474d 546e 1768 7474 7073 3a2f 2f77 7777 2e65 7861 6d70 6c65 2e63 6f6d")
  , (resp2, "4803 3330 37c1 c0bf")
  , (resp3, "88c1 611d 4d6f 6e2c 2032 3120 4f63 7420 3230 3133 2032 303a 3133 3a32 3220 474d 54c0 5a04 677a 6970 7738 666f 6f3d 4153 444a 4b48 514b 425a 584f 5157 454f 5049 5541 5851 5745 4f49 553b 206d 6178 2d61 6765 3d33 3630 303b 2076 6572 7369 6f6e 3d31")
  ]

c6 : List (List HeaderField, String)
c6 =
  [ (resp1, "4882 6402 5885 aec3 771a 4b61 96d0 7abe 9410 54d4 44a8 2005 9504 0b81 66e0 82a6 2d1b ff6e 919d 29ad 1718 63c7 8f0b 97c8 e9ae 82ae 43d3")
  , (resp2, "4883 640e ffc1 c0bf")
  , (resp3, "88c1 6196 d07a be94 1054 d444 a820 0595 040b 8166 e084 a62d 1bff c05a 839b d9ab 77ad 94e7 821d d7f2 e6c7 b335 dfdf cd5b 3960 d5af 2708 7f36 72c1 ab27 0fb5 291f 9587 3160 65c0 03ed 4ee5 b106 3d50 07")
  ]

integers : IO ()
integers = do
  let enc = \n, v => toHex (toByteString (encodeInteger n 0 v))
  check "C.1.1 encode 10/5" (enc 5 10 == "0a") (enc 5 10)
  check "C.1.2 encode 1337/5" (enc 5 1337 == "1f9a0a") (enc 5 1337)
  check "C.1.3 encode 42/8" (enc 8 42 == "2a") (enc 8 42)
  check "C.1.1 decode" (decodeInteger 5 (hex "0a") == Just (10, 1)) ""
  check "C.1.2 decode" (decodeInteger 5 (hex "1f9a0a") == Just (1337, 3)) ""
  check "C.1.3 decode" (decodeInteger 8 (hex "2a") == Just (42, 1)) ""
  check "prefix bits ignored" (decodeInteger 5 (hex "ea") == Just (10, 1)) ""
  check "truncated integer" (decodeInteger 5 (hex "1f9a") == Nothing) ""
  check "integer overflow" (decodeInteger 5 (hex "1fffffffff0f") == Nothing) ""
  check "largest integer" (decodeInteger 8 (hex "ff80feffff07") == Just (0x7FFFFFFF, 6)) ""
  check "round trip 2^31-1"
        (decodeInteger 4 (toByteString (encodeInteger 4 0 0x7FFFFFFF)) == Just (0x7FFFFFFF, 6)) ""

literals : IO ()
literals = do
  let none = newEncoder 4096 False
  -- C.2.1
  _ <- encodeStep "C.2.1" none (\_ => IncrementalIndexing) [f "custom-key" "custom-header"]
         "400a 6375 7374 6f6d 2d6b 6579 0d63 7573 746f 6d2d 6865 6164 6572"
  _ <- decodeStep "C.2.1" (newDecoder 4096 65536)
         "400a 6375 7374 6f6d 2d6b 6579 0d63 7573 746f 6d2d 6865 6164 6572"
         [f "custom-key" "custom-header"]
  -- C.2.2
  _ <- encodeStep "C.2.2" none (\_ => WithoutIndexing) [f ":path" "/sample/path"]
         "040c 2f73 616d 706c 652f 7061 7468"
  _ <- decodeStep "C.2.2" (newDecoder 4096 65536) "040c 2f73 616d 706c 652f 7061 7468"
         [f ":path" "/sample/path"]
  -- C.2.3
  _ <- encodeStep "C.2.3" none (\_ => NeverIndexed) [f "password" "secret"]
         "1008 7061 7373 776f 7264 0673 6563 7265 74"
  _ <- decodeStep "C.2.3" (newDecoder 4096 65536) "1008 7061 7373 776f 7264 0673 6563 7265 74"
         [MkHeaderField "password" "secret" True]
  -- C.2.4
  _ <- encodeStep "C.2.4" none (\_ => IncrementalIndexing) [f ":method" "GET"] "82"
  _ <- decodeStep "C.2.4" (newDecoder 4096 65536) "82" [f ":method" "GET"]
  pure ()

huffman : IO ()
huffman = do
  check "Kraft sum is 1" (kraftSum == 1073741824) (show kraftSum)
  let known = [(0, 0x1ff8, 13), (1, 0x7fffd8, 23), (9, 0xffffea, 24), (10, 0x3ffffffc, 30),
               (13, 0x3ffffffd, 30), (22, 0x3ffffffe, 30), (32, 0x14, 6), (48, 0x0, 5),
               (92, 0x7fff0, 19), (122, 0x7b, 7), (127, 0xffffffc, 28), (220, 0xffffffd, 28),
               (249, 0xffffffe, 28), (255, 0x3ffffee, 26), (256, 0x3fffffff, 30)]
  check "codes of appendix B"
        (all (\(s, c, l) => code s == c && codeLength s == l) known) ""
  let allBytes = BS.pack (map cast [the Int 0 .. 255])
  check "round trip of all bytes" (huffmanDecode (huffmanEncode allBytes) == Just allBytes) ""
  check "empty string" (huffmanDecode BS.empty == Just BS.empty) ""
  check "\"a\" with padding 111" (huffmanDecode (hex "1f") == Just "a") ""
  check "padding not all ones" (huffmanDecode (hex "18") == Nothing) ""
  check "padding of 8 bits or more" (huffmanDecode (hex "1fff") == Nothing) ""
  check "a lone byte of ones" (huffmanDecode (hex "ff") == Nothing) ""
  check "EOS in the string" (huffmanDecode (hex "ffffffff") == Nothing) ""
  check "EOS then a symbol" (huffmanDecode (hex "fffffffc") == Nothing) ""
  check "incomplete code of 15 bits" (huffmanDecode (hex "fffe") == Nothing) ""
  check "string with invalid Huffman"
        (either show (const "ok") (decodeHeaderBlock (newDecoder 4096 65536) (hex "4081ff0161"))
           == "InvalidHuffman") ""

errors : IO ()
errors = do
  let d = newDecoder 4096 65536
      res : String -> String
      res bytes = case decodeHeaderBlock d (hex bytes) of
                    Left e => show e
                    Right (fs, _) => "ok " ++ show fs
      expect : String -> String -> String -> IO ()
      expect name bytes want = check name (res bytes == want) (res bytes)
  expect "index 0" "80" "InvalidIndex 0"
  expect "index beyond the tables" "be" "InvalidIndex 62"
  expect "name index beyond the tables" "7e0161" "InvalidIndex 62"
  expect "truncated literal" "400a63" "Truncated"
  expect "truncated integer" "ff" "Truncated"
  expect "huge index" "ffffffffff0f" "IntegerOverflow"
  expect "empty block" "" "ok []"
  -- dynamic table size updates
  expect "size update to the limit" "3fe11f" "ok []"
  expect "size update above the limit" "3fe21f" "TableSizeAboveLimit 4097"
  expect "size update after a field" "8220" "LateTableSizeUpdate"
  expect "two size updates at the start" "203fe11f82" "ok [:method: GET]"
  let d100 = setDecoderTableLimit 100 d
  check "lowered limit without update"
        (either show (const "ok") (decodeHeaderBlock d100 (hex "82")) == "MissingTableSizeUpdate") ""
  case decodeHeaderBlock d100 (hex "3f4582") of
    Left e => check "lowered limit with update" False (show e)
    Right (fs, d') => do
      check "lowered limit with update" (tableMaxSize (decoderTable d') == 100) ""
      check "no update needed afterwards"
            (either show (const "ok") (decodeHeaderBlock d' (hex "82")) == "ok") ""
  -- an entry larger than the table empties it
  case decodeHeaderBlock (newDecoder 60 65536) (hex "8441 0f77 7777 2e65 7861 6d70 6c65 2e63 6f6d") of
    Left e => check "entry larger than the table" False (show e)
    Right (_, d') => do
      check "entry that fits" (tableSize (decoderTable d') == 57) ""
      case decodeHeaderBlock d' (hex "400a 6375 7374 6f6d 2d6b 6579 0d63 7573 746f 6d2d 6865 6164 6572") of
        Left e => check "entry that evicts" False (show e)
        Right (_, d'') => check "entry that evicts" (tableSize (decoderTable d'') == 55
                                                      && tableCount (decoderTable d'') == 1) ""
  case decodeHeaderBlock (newDecoder 50 65536) (hex "8441 0f77 7777 2e65 7861 6d70 6c65 2e63 6f6d") of
    Left e => check "entry larger than the table" False (show e)
    Right (_, d') => check "entry larger than the table" (tableCount (decoderTable d') == 0) ""

limits : IO ()
limits = do
  -- C.3.1 decodes to a list of size 42 + 43 + 38 + 57 = 180.
  let first = hex "8286 8441 0f77 7777 2e65 7861 6d70 6c65 2e63 6f6d"
  check "list of exactly the limit"
        (either show (const "ok") (decodeHeaderBlock (newDecoder 4096 180) first) == "ok") ""
  case decodeHeaderBlock (newDecoder 4096 179) first of
    Left (HeaderListTooLarge st) => do
      check "list above the limit" True ""
      check "table kept after a list above the limit" (tableSize (decoderTable st) == 57) ""
      -- the connection goes on with the next block of C.3
      case decodeHeaderBlock (setDecoderMaxListSize 65536 st) (hex "8286 84be 5808 6e6f 2d63 6163 6865") of
        Left e => check "next block after a list above the limit" False (show e)
        Right (fs, st') => check "next block after a list above the limit"
                                 (length fs == 5 && tableSize (decoderTable st') == 110) ""
    Left e => check "list above the limit" False (show e)
    Right _ => check "list above the limit" False "accepted"

encoderPolicy : IO ()
encoderPolicy = do
  let blocks = [ [f ":method" "GET", f ":path" "/", f "authorization" "Basic dXNlcjpwYXNz",
                  f "cookie" "a=1", f "cookie" "session=0123456789abcdef0123", f "x-big" (pack (replicate 5000 'x'))]
               , [f ":method" "GET", f ":path" "/", f "authorization" "Basic dXNlcjpwYXNz",
                  f "cookie" "a=1", f "cookie" "session=0123456789abcdef0123", MkHeaderField "x-secret" "1" True]
               ]
  for_ [False, True] $ \huff => do
    let go : EncoderState -> DecoderState -> List (List HeaderField) -> List String -> List String
        go _ _ [] acc = reverse acc
        go e d (b :: bs) acc =
          let (bytes, e') = encodeHeaderBlock e b in
          case decodeHeaderBlock d (toByteString bytes) of
            Left err => reverse (("error " ++ show err) :: acc)
            Right (fs, d') =>
              go e' d' bs
                 ((show (map (\x => x.name) fs == map (\x => x.name) b && map (\x => x.value) fs == map (\x => x.value) b)
                   ++ " " ++ show (length (BS.unpack (toByteString bytes)))
                   ++ " " ++ show (showTable (encoderTable e') == showTable (decoderTable d'))
                   ++ " " ++ show (map (\x => x.sensitive) fs)) :: acc)
    putStrLn ("default policy, huffman " ++ show huff ++ ":")
    traverse_ (\l => putStrLn ("  " ++ l)) (go (newEncoder 4096 huff) (newDecoder 4096 1000000) blocks [])
  -- the table of the encoder holds :method/:path from the static table only,
  -- the long cookie and not the big field
  let (_, e) = encodeHeaderBlock (newEncoder 4096 True) (case blocks of { (b :: _) => b; [] => [] })
  printTable (encoderTable e)
  -- size updates: lower to 100, then raise to 200: both are signalled
  let e1 = setEncoderTableLimit 200 (setEncoderTableLimit 100 (newEncoder 4096 False))
      (b1, e2) = encodeHeaderBlock e1 [f ":method" "GET"]
  check "size updates signalled" (toHex (toByteString b1) == "3f453fa90182") (toHex (toByteString b1))
  let d1 = setDecoderTableLimit 200 (newDecoder 4096 65536)
  check "size updates accepted"
        (the String (case decodeHeaderBlock d1 (toByteString b1) of
                       Left err => show err
                       Right (_, d) => show (tableMaxSize (decoderTable d))) == "200") ""
  let (b2, _) = encodeHeaderBlock e2 [f ":method" "GET"]
  check "no update in the next block" (toHex (toByteString b2) == "82") (toHex (toByteString b2))
  -- the cap of the encoder: a peer allowing 1 MB still gets a 4096 table
  let (b3, e3) = encodeHeaderBlock (setEncoderTableLimit 1048576 (newEncoder 4096 False)) [f ":method" "GET"]
  check "cap of the encoder" (toHex (toByteString b3) == "82" && tableMaxSize (encoderTable e3) == 4096)
        (toHex (toByteString b3))

main : IO ()
main = do
  integers
  literals
  putStrLn "C.3 (requests without Huffman):"
  sequenceTest "C.3" 4096 False c3
  putStrLn "C.4 (requests with Huffman):"
  sequenceTest "C.4" 4096 True c4
  putStrLn "C.5 (responses without Huffman, table of 256):"
  sequenceTest "C.5" 256 False c5
  putStrLn "C.6 (responses with Huffman, table of 256):"
  sequenceTest "C.6" 256 True c6
  huffman
  errors
  limits
  encoderPolicy
