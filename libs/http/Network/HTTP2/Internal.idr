||| Buffer primitives in the form that loops over buffers need: functions of
||| the `%World` token, so that a loop that writes is a self tail call (which
||| every back end turns into a jump).  The pure reads of buffers that are
||| never written again are those of `Data.ByteString.Internal`.  Internal to
||| the `http` library.
module Network.HTTP2.Internal

import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal

%default total

%foreign "scheme:blodwen-buffer-setbyte"
         "RefC:setBufferUInt8"
         "node:lambda:(buf,offset,value)=>buf.writeUInt8(value, offset)"
prim__set8 : Buffer -> Int -> Bits8 -> PrimIO ()

%foreign "scheme:blodwen-new-buffer"
         "RefC:newBuffer"
         "node:lambda:s=>Buffer.alloc(s)"
prim__newBuf : Int -> PrimIO Buffer

||| Write a byte of a buffer, passing the world token by hand.
export %inline
wset8 : Buffer -> Int -> Bits8 -> (1 w : %World) -> IORes ()
wset8 = prim__set8

||| Make a byte string of at most `cap` bytes with a function of a fresh
||| buffer of that size that returns how many bytes it wrote from the start,
||| or a negative number for failure (`Nothing`).  The function must not
||| keep the buffer.
export
createUpTo : (cap : Int) -> (Buffer -> (1 w : %World) -> IORes Int) -> Maybe ByteString
createUpTo cap fill = unsafePerformIO (fromPrim run)
  where
    run : (1 w : %World) -> IORes (Maybe ByteString)
    run w = case prim__newBuf (if cap <= 0 then 1 else cap) w of
      MkIORes buf w1 => case fill buf w1 of
        MkIORes n w2 =>
          MkIORes (if n < 0 then Nothing else Just (UnsafeBS buf 0 (if n > cap then cap else n))) w2
