import Data.ByteString as BS
import Data.ByteString.Builder as B
import Data.List
import System.File
import System.File.ByteString as BSF

%default total
%ambiguity_depth 10

t : Show a => String -> a -> IO ()
t name v = putStrLn (name ++ ": " ++ show v)

-- Show only whether an operation worked or the kind of error it gave.
res : Either FileError a -> String
res (Right _) = "ok"
res (Left FileNotFound) = "file not found"
res (Left (GenericFileError _)) = "error"
res (Left _) = "other error"

wres : Either (FileError, Int) () -> String
wres (Right ()) = "ok"
wres (Left (FileNotFound, _)) = "file not found"
wres (Left _) = "error"

counting : Nat -> List Bits8
counting n = go n []
  where
    go : Nat -> List Bits8 -> List Bits8
    go Z acc = acc
    go (S k) acc = go k (cast k :: acc)

covering
main : IO ()
main = do
  let allBytes = BS.pack (map cast (counting 256))
  putStrLn "-- whole files"
  r <- BSF.writeFile "test_bs_all.bin" allBytes
  putStrLn ("write: " ++ wres r)
  Right back <- BSF.readFile "test_bs_all.bin"
    | Left err => putStrLn ("read failed: " ++ show err)
  t "round trip" (back == allBytes, BS.length back)
  t "bytes >= 0x80" (BS.index 128 back, BS.index 255 back, BS.index 0 back)

  r <- BSF.writeFile "test_bs_empty.bin" BS.empty
  putStrLn ("write empty: " ++ wres r)
  Right e <- BSF.readFile "test_bs_empty.bin"
    | Left err => putStrLn ("read failed: " ++ show err)
  t "empty file" (BS.length e, BS.null e)

  r <- BSF.writeFile "test_bs_all.bin" (BS.pack [1, 2, 3])
  Right shorter <- BSF.readFile "test_bs_all.bin"
    | Left err => putStrLn ("read failed: " ++ show err)
  t "truncated" shorter

  r <- BSF.appendFile "test_bs_all.bin" (BS.pack [4, 5])
  r' <- BSF.appendFile "test_bs_new.bin" (BS.pack [0, 255])
  putStrLn ("append: " ++ wres r ++ " " ++ wres r')
  Right appended <- BSF.readFile "test_bs_all.bin"
    | Left err => putStrLn ("read failed: " ++ show err)
  Right created <- BSF.readFile "test_bs_new.bin"
    | Left err => putStrLn ("read failed: " ++ show err)
  t "appended" (appended, created)

  putStrLn "-- slices"
  -- Only the bytes of the slice are written.
  let sliced = BS.drop 2 (BS.take 6 (BS.pack [9, 9, 1, 2, 3, 4, 9, 9]))
  r <- BSF.writeFile "test_bs_slice.bin" sliced
  Right gotSlice <- BSF.readFile "test_bs_slice.bin"
    | Left err => putStrLn ("read failed: " ++ show err)
  t "slice written" (wres r, gotSlice)

  putStrLn "-- errors"
  r1 <- BSF.readFile "test_bs_missing.bin"
  putStrLn ("read missing: " ++ res r1)
  r2 <- BSF.writeFile "test_bs_no_such_dir/x.bin" (BS.pack [1])
  putStrLn ("write to a missing directory: " ++ wres r2)

  putStrLn "-- handles"
  Right _ <- BSF.writeFile "test_bs_h.bin" (BS.pack (counting 100))
    | Left _ => putStrLn "write failed"
  Right h <- openFile "test_bs_h.bin" Read
    | Left err => putStrLn ("open failed: " ++ show err)
  Right a <- hGet h 3
    | Left err => putStrLn ("hGet failed: " ++ show err)
  Right z <- hGet h 0
    | Left err => putStrLn ("hGet failed: " ++ show err)
  Right b <- hGet h 10
    | Left err => putStrLn ("hGet failed: " ++ show err)
  t "pieces" (a, z, b)
  Right rest <- hGet h 1000
    | Left err => putStrLn ("hGet failed: " ++ show err)
  t "rest" (BS.length rest, BS.take 3 rest, BS.drop 84 rest)
  Right eof <- hGet h 10
    | Left err => putStrLn ("hGet failed: " ++ show err)
  t "at end of file" (BS.length eof)
  Right eof0 <- hGet h 0
    | Left err => putStrLn ("hGet failed: " ++ show err)
  t "at end of file, 0 bytes" (BS.length eof0)
  closeFile h

  Right h <- openFile "test_bs_h.bin" Read
    | Left err => putStrLn ("open failed: " ++ show err)
  Right x <- hGet h 5
    | Left err => putStrLn ("hGet failed: " ++ show err)
  Right xs <- BSF.hGetContents h
    | Left err => putStrLn ("hGetContents failed: " ++ show err)
  t "hGetContents after hGet" (x, BS.length xs, BS.take 2 xs)
  closeFile h

  Right w <- openFile "test_bs_w.bin" WriteTruncate
    | Left err => putStrLn ("open failed: " ++ show err)
  ra <- hPut w (BS.pack [1, 2])
  rb <- hPut w BS.empty
  rc <- hPut w (BS.drop 1 (BS.pack [0, 200, 201]))
  closeFile w
  putStrLn ("hPut: " ++ wres ra ++ " " ++ wres rb ++ " " ++ wres rc)
  Right wrote <- BSF.readFile "test_bs_w.bin"
    | Left err => putStrLn ("read failed: " ++ show err)
  t "hPut content" wrote

  putStrLn "-- large file"
  -- bigger than the first chunks that hGetContents reads (64 KiB, 128 KiB...)
  let big = toByteString (B.bytes (counting 300000) <+> B.bytes (counting 70000))
  r <- BSF.writeFile "test_bs_big.bin" big
  Right bigBack <- BSF.readFile "test_bs_big.bin"
    | Left err => putStrLn ("read failed: " ++ show err)
  t "big" (wres r, BS.length big, BS.length bigBack, bigBack == big)
  t "big exact chunk sizes" (map (\n => (n, BS.length (BS.take n big))) [65536, 65536 + 131072])
  Right h <- openFile "test_bs_big.bin" Read
    | Left err => putStrLn ("open failed: " ++ show err)
  Right part <- hGet h 100000
    | Left err => putStrLn ("hGet failed: " ++ show err)
  t "big hGet" (BS.length part, part == BS.take 100000 big)
  closeFile h
  -- a file of exactly 64 KiB, so that the first chunk is full and the next is empty
  let exact = BS.pack (counting 65536)
  _ <- BSF.writeFile "test_bs_exact.bin" exact
  Right exactBack <- BSF.readFile "test_bs_exact.bin"
    | Left err => putStrLn ("read failed: " ++ show err)
  t "exactly one chunk" (BS.length exactBack, exactBack == exact)
