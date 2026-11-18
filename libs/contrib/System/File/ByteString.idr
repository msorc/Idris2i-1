||| Reading and writing `ByteString`s from files and handles, organised like
||| `System.File.Buffer` of `base`.  Files are opened in binary mode: nothing
||| is translated.
|||
||| `readFile`, `writeFile` and `appendFile` have the names of the functions
||| of `System.File` that work on strings, so import this module qualified
||| (`import System.File.ByteString as BSF`) and write `BSF.readFile`; an
||| unqualified `readFile` is ambiguous when both modules are imported and
||| the types do not say which is meant.
module System.File.ByteString

import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal
import System.File

%default total

||| Read up to `n` bytes from a file handle.  The result is shorter than `n`
||| only if the end of the file is reached first (it is empty at the end of
||| the file), so it is not only what one call of `fread` returns on a pipe.
||| `Left` if reading fails.
|||
||| @ fh the handle to read from
||| @ n  the most bytes to read
export
hGet : HasIO io => (fh : File) -> (n : Nat) -> io (Either FileError ByteString)
hGet fh n = createIO (cast n) (\buf => readUpTo buf (cast n) 0 (cast n))
  where
    -- Keep reading until `remaining` bytes have come, or a read gives none.
    -- The fuel is the number of bytes wanted: every step reads at least one.
    readUpTo : Buffer -> (wanted : Int) -> (done : Int) -> Nat -> io (Either FileError Int)
    readUpTo _ _ done Z = pure (Right done)
    readUpTo buf wanted done (S k) =
      if done >= wanted then pure (Right done) else
      do Right got <- readBufferData fh buf done (wanted - done)
           | Left err => pure (Left err)
         if got <= 0
            then do failed <- fileError fh
                    if failed then pure (Left FileReadError) else pure (Right done)
            else readUpTo buf wanted (done + got) k

-- The size of the first chunk that `hGetContents` reads, and the largest.
firstChunk : Nat
firstChunk = 65536

largestChunk : Nat
largestChunk = 16777216

||| Read from a file handle until the end of the file.  The result is built
||| from chunks, the first of 64 KiB and each twice as big as the one before
||| up to 16 MiB, and one final copy, so memory use at the end is twice the
||| size of the data.  `Left` if reading fails.  (`covering`, not `total`: it
||| ends when the file does.)
export covering
hGetContents : HasIO io => (fh : File) -> io (Either FileError ByteString)
hGetContents fh = go firstChunk []
  where
    go : Nat -> List ByteString -> io (Either FileError ByteString)
    go size acc =
      do Right chunk <- hGet fh size
           | Left err => pure (Left err)
         if length chunk < size
            then pure (Right (Data.ByteString.concat (reverse (chunk :: acc))))
            else go (if size >= largestChunk then size else size * 2) (chunk :: acc)

||| Write a byte string to a file handle.  On a write error, the result gives
||| the error and the number of bytes that were written, as `writeBufferData`
||| does.
export
hPut : HasIO io => (fh : File) -> ByteString -> io (Either (FileError, Int) ())
hPut fh bs = writeBufferData fh (unsafeBuffer bs) (unsafeOffset bs) (lengthInt bs)

||| Read a whole file, as `hGetContents` does (`covering`, not `total`, for
||| the same reason).
|||
||| @ fn the name of the file
export covering
readFile : HasIO io => (fn : String) -> io (Either FileError ByteString)
readFile fn =
  do Right fh <- openFile fn Read
       | Left err => pure (Left err)
     r <- hGetContents fh
     closeFile fh
     pure r

||| Write a byte string to a file, which is created, or emptied if it exists.
||| Returns the number of bytes that were written upon a write error.
|||
||| @ fn the name of the file
export
writeFile : HasIO io => (fn : String) -> ByteString -> io (Either (FileError, Int) ())
writeFile fn bs =
  do Right fh <- openFile fn WriteTruncate
       | Left err => pure (Left (err, 0))
     r <- hPut fh bs
     closeFile fh
     pure r

||| Add a byte string at the end of a file, which is created if it does not
||| exist.  Returns the number of bytes that were written upon a write error.
|||
||| @ fn the name of the file
export
appendFile : HasIO io => (fn : String) -> ByteString -> io (Either (FileError, Int) ())
appendFile fn bs =
  do Right fh <- openFile fn Append
       | Left err => pure (Left (err, 0))
     r <- hPut fh bs
     closeFile fh
     pure r
