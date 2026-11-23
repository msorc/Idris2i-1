import Data.ByteString as BS
import Data.ByteString.Builder as B
import Data.List
import Network.HTTP.Types
import Network.HTTP.Parser
import Network.HTTP.Chunked

%default total

-- Feed the pieces; the data of all the steps, joined, and how it ended.
-- The rest is the rest of the last piece fed and the pieces not fed.
decodeAll : ChunkDecoder -> List ByteString -> List ByteString -> String
decodeAll d acc [] = "More data=" ++ show (BS.concat (reverse acc)) ++ " decoded=" ++ show (decodedLength d)
decodeAll d acc (x :: xs) = case decodeChunks d x of
  More ps d' => decodeAll d' (reverse ps ++ acc) xs
  End ps hs rest => "End data=" ++ show (BS.concat (reverse acc ++ ps)) ++ " trailers=" ++ show hs
                    ++ " rest=" ++ show (BS.concat (rest :: xs))
  ChunkFailed e => "Failed " ++ show e

whole : ChunkLimits -> ByteString -> String
whole l bs = decodeAll (chunkDecoder l) [] [bs]

-- Every split in two, and byte by byte, give the outcome of the whole.
splits : ChunkLimits -> ByteString -> String
splits l bs =
  let w = whole l bs
      ways = map (\k => [BS.take k bs, BS.drop k bs]) [0 .. BS.length bs]
             ++ [map BS.singleton (BS.unpack bs)]
      bad = filter (\ps => decodeAll (chunkDecoder l) [] ps /= w) ways
  in case bad of
       [] => "same in " ++ show (length ways) ++ " splits"
       (ps :: _) => "DIFFERENT for " ++ show ps ++ ": " ++ decodeAll (chunkDecoder l) [] ps

check : ChunkLimits -> String -> ByteString -> IO ()
check l name bs = do
  putStrLn (name ++ ": " ++ whole l bs)
  putStrLn ("  " ++ splits l bs)

tiny : ChunkLimits
tiny = MkChunkLimits 8 ({ maxHeadSize := 40 } defaultLimits)

main : IO ()
main = do
  putStrLn "== valid"
  check defaultChunkLimits "simple" "5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n"
  check defaultChunkLimits "with rest" "5\r\nhello\r\n0\r\n\r\nGET / HTTP/1.1\r\n"
  check defaultChunkLimits "hex sizes" "A\r\n0123456789\r\na\r\nabcdefghij\r\n000\r\n\r\n"
  check defaultChunkLimits "extensions" "5;name=value\r\nhello\r\n6 ; a=\"b c\";d\r\n world\r\n0;last\r\n\r\n"
  check defaultChunkLimits "trailers" "5\r\nhello\r\n0\r\nX-Checksum: abc\r\nX-Other: 1\r\n\r\nNEXT"
  check defaultChunkLimits "no chunks" "0\r\n\r\n"
  check defaultChunkLimits "unfinished data" "5\r\nhel"
  check defaultChunkLimits "unfinished trailer" "0\r\nX-A: 1\r\n"
  putStrLn "== invalid"
  check defaultChunkLimits "no digits" "\r\nhello\r\n0\r\n\r\n"
  check defaultChunkLimits "not hex" "g\r\nhello\r\n0\r\n\r\n"
  check defaultChunkLimits "sign" "+5\r\nhello\r\n0\r\n\r\n"
  check defaultChunkLimits "junk after size" "5x\r\nhello\r\n0\r\n\r\n"
  check defaultChunkLimits "space then junk" "5 x\r\nhello\r\n0\r\n\r\n"
  check defaultChunkLimits "bare LF after size" "5\nhello\r\n0\r\n\r\n"
  check defaultChunkLimits "CR without LF" "5\rhello\r\n0\r\n\r\n"
  check defaultChunkLimits "data too long" "5\r\nhello!\r\n0\r\n\r\n"
  check defaultChunkLimits "data without CRLF" "5\r\nhello5\r\nhello\r\n0\r\n\r\n"
  check defaultChunkLimits "data with LF only" "5\r\nhello\n0\r\n\r\n"
  check defaultChunkLimits "size of 2^60" "1000000000000000\r\n"
  check defaultChunkLimits "size of 2^60 - 1" "fffffffffffffff\r\n"
  check defaultChunkLimits "control in extension" "5;a\1b\r\nhello\r\n0\r\n\r\n"
  check tiny "extension at the limit" "5;abcdefg\r\nhello\r\n0\r\n\r\n"
  check tiny "extension too long" "5;abcdefgh\r\nhello\r\n0\r\n\r\n"
  check defaultChunkLimits "bad trailer" "0\r\nX-A : 1\r\n\r\n"
  check defaultChunkLimits "obs-fold in trailer" "0\r\nX-A: 1\r\n 2\r\n\r\n"
  check tiny "trailer too large" "0\r\nX-A: 0123456789\r\nX-B: 0123456789\r\nX-C: 01\r\n\r\n"
  putStrLn "== encoding"
  let enc = B.toByteString (encodeChunked ["hello", "", " world", BS.replicate 26 97] (headersFromPairs [("X-T", "1")]))
  putStrLn (show enc)
  putStrLn ("decoded: " ++ whole defaultChunkLimits enc)
  putStrLn (show (B.toByteString (encodeChunk "") ) ++ " " ++ show (B.toByteString (encodeLastChunk emptyHeaders)))
  -- Round trips of bodies of every length up to 40, in pieces of 7 bytes.
  let body : Nat -> ByteString
      body n = BS.pack (map (\i => cast (i * 7 + 3)) [1 .. n])
      pieces : ByteString -> List ByteString
      pieces bs = if BS.length bs <= 7 then [bs] else BS.take 7 bs :: pieces (assert_smaller bs (BS.drop 7 bs))
      roundTrip : Nat -> Bool
      roundTrip n = let b = body n
                        e = B.toByteString (encodeChunked (pieces b) emptyHeaders)
                    in case decodeChunks (chunkDecoder defaultChunkLimits) e of
                         End ps _ rest => BS.concat ps == b && BS.null rest
                         _ => False
  putStrLn ("round trips: " ++ show (all roundTrip [0 .. 40]))
