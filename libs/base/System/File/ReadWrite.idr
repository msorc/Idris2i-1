module System.File.ReadWrite

import public Data.Fuel

import Data.SnocList

import System.File.Handle
import public System.File.Error
import System.File.Support
import public System.File.Types
import System.FFI

%default total

%foreign supportC "idris2_seekLine"
         supportNode "seekLine"
prim__seekLine : FilePtr -> PrimIO Int

%foreign supportC "idris2_readLine"
         supportNode "readLine"
prim__readLine : FilePtr -> PrimIO (Ptr String)

%foreign supportC "idris2_readChars"
         supportNode "readChars"
prim__readChars : Int -> FilePtr -> PrimIO (Ptr String)
%foreign "C:fgetc,libc 6"
         supportNode "readChar"
prim__readChar : FilePtr -> PrimIO Int

%foreign "RefC:idris2_refc_writeLine"
         supportC "idris2_writeLine"
         supportNode "writeLine"
prim__writeLine : FilePtr -> String -> PrimIO Int

%foreign supportC "idris2_eof"
         "node:lambda:f=>(f.eof?1:0)"
prim__eof : FilePtr -> PrimIO Int

%foreign "C:idris2_free, libidris2_support, idris_memory.h"
         "javascript:lambda:()=>undefined"
prim__freeString : Ptr String -> PrimIO ()

-- `prim__getString` as an IO action: the string must be copied before the
-- pointer is freed, and `prim__getString` is pure, so that once the code is
-- specialised and inlined, the copy may be moved after the call of `free`.
%foreign "C:idris2_getString, libidris2_support, idris_support.h"
         "javascript:lambda:x=>x"
prim__getStringIO : Ptr String -> PrimIO String

-- The functions of this module (and of System.File.Handle) call `pure (Right
-- x)` instead of `ok x`, and `prim__freeString` instead of `free`: when a
-- module that only imports System.File calls them at `IO`, their `%spec`
-- copies are elaborated there, where the names of System.File.Support and
-- System.FFI are not in scope, so referring to these modules would leave the
-- copies calling the generic code (see TTImp.PartialEval).

%foreign supportC "idris2_removeFile"
         supportNode "removeFile"
prim__removeFile : String -> PrimIO Int

||| Seek through the next newline.
||| This is @fGetLine@ without the overhead of copying
||| any characters.
|||
||| @ h the file handle to seek through
%spec hio
export
covering
fSeekLine : {auto hio : HasIO io} -> (h : File) -> io (Either FileError ())
fSeekLine (FHandle f)
    = do res <- primIO (prim__seekLine f)
         if res /= 0
            then returnError
            else pure (Right ())


||| Get a garbage collected String from a Ptr String and and free the original
%spec hio
export
getStringAndFree : {auto hio : HasIO io} -> File -> Ptr String -> io (Either FileError String)
getStringAndFree f res
    = if prim__nullPtr res /= 0
         then if !(fileError f) then returnError else pure @{Compose} ""
         else do s <- primIO (prim__getStringIO res)
                 primIO (prim__freeString res)
                 pure (Right s)

||| Get the next line from the given file handle, returning the empty string if
||| nothing was read.
|||
||| @ h the file handle to get the line from
%spec hio
export
covering
fGetLine : {auto hio : HasIO io} -> (h : File) -> io (Either FileError String)
fGetLine ff@(FHandle f)
    = do res <- primIO (prim__readLine f)
         getStringAndFree ff res

||| Get a number of characters from the given file handle.
|||
||| @ h   the file handle to read from
||| @ max the number of characters to read
%spec hio
export
fGetChars : {auto hio : HasIO io} -> (h : File) -> (max : Int) -> io (Either FileError String)
fGetChars ff@(FHandle f) max
    = do res <- primIO (prim__readChars max f)
         getStringAndFree ff res

||| Get the next character from the given file handle.
|||
||| @ h the file handle to read from
%spec hio
export
fGetChar : {auto hio : HasIO io} -> (h : File) -> io (Either FileError Char)
fGetChar h@(FHandle f)
    = do c <- primIO (prim__readChar f)
         ferr <- fileError h
         if ferr
            then returnError
            else pure (Right (cast c))

||| Write the given string to the file handle.
|||
||| @ h   the file handle to write to
||| @ str the string to write
%spec hio
export
fPutStr : {auto hio : HasIO io} -> (h : File) -> (str : String) -> io (Either FileError ())
fPutStr (FHandle f) str
    = do res <- primIO (prim__writeLine f str)
         if res == 0
            then returnError
            else pure (Right ())

||| Write the given string, followed by a newline, to the file handle.
|||
||| @ fh  the file handle to write to
||| @ str the string to write
%spec hio
export
fPutStrLn : {auto hio : HasIO io} -> (fh : File) -> (str : String) -> io (Either FileError ())
fPutStrLn fh str = fPutStr fh (str ++ "\n")

||| Check whether the end-of-file indicator for the given file handle is set.
|||
||| @ h the file handle to check
%spec hio
export
fEOF : {auto hio : HasIO io} -> (h : File) -> io Bool
fEOF (FHandle f)
    = do res <- primIO (prim__eof f)
         pure (res /= 0)

||| Read all the remaining contents of a file handle
%spec hio
export
covering
fRead : {auto hio : HasIO io} -> (h : File) -> io (Either FileError String)
fRead h = fRead' h [<]
  where
    fRead' : HasIO io' => (h : File) -> (acc : SnocList String) -> io' (Either FileError String)
    fRead' h acc = do
      if !(fEOF h)
         then pure $ Right $ concat acc
         else do
             Right line <- fGetLine h
                | Left err => pure $ Left err
             fRead' h $ acc :< line

||| Delete the file at the given name.
|||
||| @ fname the file to delete
%spec hio
export
removeFile : {auto hio : HasIO io} -> (fname : String) -> io (Either FileError ())
removeFile fname
    = do res <- primIO (prim__removeFile fname)
         if res == 0
            then pure (Right ())
            else returnError

||| Read a number of lines into an accumulator, optionally starting at an offset
||| in the given file handle. Requires `Fuel` to run since the operation is
||| total but may run indefinitely; the functions `limit` and `forever` help
||| with providing `Fuel`.
|||
||| On success, returns a tuple of whether the EOF was reached (if it wasn't, we
||| ran out of fuel first) and the lines accumulated.
|||
||| Note: each line will still have a newline character at the end.
|||
||| @ acc    the accumulator to read the lines onto
||| @ offset the offset to start reading at
||| @ fuel   an amount of `Fuel`
||| @ h      the file handle to read from
readLinesOnto : HasIO io => (acc : List String) ->
                            (offset : Nat) ->
                            (fuel : Fuel) ->
                            (h : File) ->
                            io (Either FileError (Bool, List String))
readLinesOnto acc _ Dry h = pure (Right (False, reverse acc))
readLinesOnto acc offset (More fuel) h
  = do False <- fEOF h
         | True => pure $ Right (True, reverse acc)
       -- The recursive calls are in tail position (which they are not through
       -- the `Compose` monad of `io` and `Either`), so that reading a file of
       -- many lines does not need a deep stack.
       case offset of
            (S offset') => do Right () <- fSeekLine h
                                | Left err => pure (Left err)
                              readLinesOnto acc offset' (More fuel) h
            0           => do Right str <- fGetLine h
                                | Left err => pure (Left err)
                              readLinesOnto (str :: acc) 0 fuel h

||| Read a chunk of a file in a line-delimited fashion.
||| You can use this function to read an entire file
||| as with @readFile@ by reading until @forever@ or by
||| iterating through pages until hitting the end of
||| the file.
|||
||| The @limit@ function can provide you with enough
||| fuel to read exactly a given number of lines.
|||
||| On success, returns a tuple of whether the end of
||| the file was reached or not and the lines read in
||| from the file.
|||
||| Note that each line will still have a newline
||| character at the end.
|||
||| Important: because we are chunking by lines, this
||| function's totality depends on the assumption that
||| no single line in the input file is infinite.
|||
||| @ offset the offset to start reading at
||| @ until  the `Fuel` limiting how far we can read
||| @ fname  the name of the file to read
%spec hio
export
readFilePage : {auto hio : HasIO io} -> (offset : Nat) -> (until : Fuel) -> (fname :  String) ->
                           io (Either FileError (Bool, List String))
readFilePage offset fuel fname
  = withFile fname Read pure $
      readLinesOnto [] offset fuel

||| Read the entire file at the given name. This function is `partial` since
||| there is no guarantee that the given file isn't infinite.
|||
||| @ fname the name of the file to read
%spec hio
export
covering
readFile : {auto hio : HasIO io} -> (fname : String) -> io (Either FileError String)
readFile = (map $ map (fastConcat . snd)) . readFilePage 0 forever

||| Write the given string to the file at the specified name. Opens the file
||| with the `WriteTruncate` mode.
||| (If you have a file handle (a `File`), you may be looking for `fPutStr`.)
|||
||| @ filePath the file to write to
||| @ contents the string to write to the file
%spec hio
export
writeFile : {auto hio : HasIO io} ->
            (filePath : String) -> (contents : String) ->
            io (Either FileError ())
writeFile file contents
  = withFile file WriteTruncate pure $
      flip fPutStr contents

||| Append the given string to the file at the specified name. Opens the file in
||| with the `Append` mode.
|||
||| @ filePath the file to write to
||| @ contents the string to write to the file
%spec hio
export
appendFile : {auto hio : HasIO io} ->
             (filePath : String) -> (contents : String) ->
             io (Either FileError ())
appendFile file contents
  = withFile file Append pure $
      flip fPutStr contents
