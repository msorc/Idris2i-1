module Libraries.Utils.Binary

import Data.Buffer

import System
import System.Errno
import System.File

-- Serialising data as binary. Provides an interface TTC which allows
-- reading and writing to chunks of memory, "Binary", which can be written
-- to and read from files.

%default covering

public export
record Binary where
  constructor MkBin
  buf : Buffer
  -- (Int, not Integer: these are updated at every byte read or written)
  loc : Int
  size : Int -- Capacity
  used : Int -- Amount used

export
newBinary : Buffer -> Int -> Binary
newBinary b s = MkBin b 0 s 0

%inline export
blockSize : Int
blockSize = 655360

%inline export
avail : Binary -> Int
avail c = (size c - loc c) - 1

%inline export
toRead : Binary -> Int
toRead c = used c - loc c

%inline export
appended : Int -> Binary -> Binary
appended i (MkBin b loc s used) = MkBin b (loc+i) s (used + i)

%inline export
incLoc : Int -> Binary -> Binary
incLoc i c = { loc $= (+i) } c

export
dumpBin : Binary -> IO ()
dumpBin chunk
   = do -- printLn !(traverse bufferData' (map buf done))
        printLn !(bufferData' (buf chunk))
        -- printLn !(traverse bufferData' (map buf rest))

export
fromBuffer : Buffer -> IO Binary
fromBuffer buf
    = do len <- rawSize buf
         pure (MkBin buf 0 len len)

%foreign "C:rename, libc 6, stdio.h"
prim__rename : (from : String) -> (to : String) -> PrimIO Int

||| Write the binary to a file, which is replaced as a whole: the data are
||| written under a temporary name, which is then renamed.  So a process that
||| reads the file (another build in the same directory), or a process that
||| writes it and is stopped half-way (a parallel build that stops on an
||| error), never sees a file that is cut short.
export
writeToFile : (fname : String) -> Binary -> IO (Either FileError ())
writeToFile fname c
    = do pid <- getPID
         let tmp = fname ++ ".tmp-" ++ show pid
         Right () <- writeBufferToFile tmp (buf c) (cast $ used c)
               | Left (err, size) => do ignore $ removeFile tmp
                                        pure (Left err)
         0 <- primIO $ prim__rename tmp fname
           | _ => do -- (the `rename` of Windows does not replace a file)
                     ignore $ removeFile fname
                     0 <- primIO $ prim__rename tmp fname
                       | _ => do err <- getErrno
                                 ignore $ removeFile tmp
                                 pure (Left (GenericFileError err))
                     pure (Right ())
         pure (Right ())

export
readFromFile : (fname : String) -> IO (Either FileError Binary)
readFromFile fname
    = do Right b <- createBufferFromFile fname
               | Left err => pure (Left err)
         bsize <- rawSize b
         pure (Right (MkBin b 0 bsize bsize))

||| The first `max` bytes of a file, or all of it if it is shorter. Reading
||| past them fails as at the end of a file.
export
readPrefixFromFile : (fname : String) -> (max : Int) -> IO (Either FileError Binary)
readPrefixFromFile fname max
    = do Right f <- openFile fname Read
               | Left err => pure (Left err)
         Just b <- newBuffer max
               | Nothing => do closeFile f
                               pure (Left FileReadError)
         Right got <- readBufferData f b 0 max
               | Left err => do closeFile f
                                pure (Left err)
         closeFile f
         pure (Right (MkBin b 0 max got))
