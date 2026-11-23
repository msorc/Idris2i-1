module Bytes

import Data.Buffer

%default total

-- A pure read of a byte, through a foreign function of the runtime that its
-- header defines `static inline`, and an `%inline` wrapper of it.
%foreign "RefC:getBufferUInt8"
prim__byteAt : Buffer -> Int -> Bits8

export %inline
byteAt : Buffer -> Int -> Bits8
byteAt = prim__byteAt

-- A write, in IO, through a foreign function with no result.
%foreign "RefC:setBufferUInt8"
prim__setByte : Buffer -> Int -> Bits8 -> PrimIO ()

export %inline
setByte : Buffer -> Int -> Bits8 -> IO ()
setByte b i w = fromPrim (prim__setByte b i w)
