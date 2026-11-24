||| The type `ByteString`, alone, so that `Data.ByteString` can re-export the
||| type without re-exporting the unsafe operations of
||| `Data.ByteString.Internal`.
|||
||| Idris2i-1 re-exports whole modules (`import public`), and the constructor of
||| a type has to be visible to the module that builds on it, so the type is in
||| a module of its own.  The constructor is therefore visible to a program
||| that imports `Data.ByteString`, but programs must not use it: building a
||| slice by hand can break its invariant (see `Data.ByteString.Internal`), and
||| its name says so.
module Data.ByteString.Types

import Data.Buffer

%default total

||| An immutable sequence of bytes: a slice of a buffer that is never written
||| after it has been filled.  Slicing (`take`, `drop`, `splitAt`...) takes
||| constant time and shares the buffer; `Data.ByteString.copy` makes a
||| slice that owns its bytes.
|||
||| The constructor is for `Data.ByteString.Internal` only.  The fields are
||| the buffer, the offset of the first byte in it and the number of bytes,
||| and `0 <= offset`, `0 <= length` and `offset + length <= size of the
||| buffer` must hold.
public export
data ByteString : Type where
  UnsafeBS : (buf : Buffer) -> (off : Int) -> (len : Int) -> ByteString
