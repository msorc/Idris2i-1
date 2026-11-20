||| The layout of the elements of an array (see
||| docs/source/backends/refc-flat-layout.rst).
|||
||| The RefC back end stores the elements of an `IOArray` (and of the arrays
||| of Data.Linear.Array) inline, as C numbers, when their type has a `Flat`
||| implementation other than the default one: the primitive numbers and
||| `Char`, and the records of one constructor whose fields are all stored
||| raw (`Double`, `Int`, `Int64`, `Bits64`), for which the compiler makes
||| the implementation where the record is declared (in a module that has
||| this one among its public imports).  The other back ends ignore the
||| layout.  An array records the layout it was made with, so code that reads
||| or writes it with another `Flat` (the default one, in code that is generic
||| in the type of the elements) reads and writes it correctly, only slower.
module Data.IOArray.Flat

import Data.IOArray.Prims

%default total

||| The layout of the elements of an array of `a`: a code that the back ends
||| read.  0 is the layout of values (a pointer each); the low byte of the
||| others is 1 (a primitive, whose type is in the next byte) or 2 (a record
||| of raw fields, whose number is in the next two bytes and whose tag in the
||| two bytes after).
export
record Layout (0 a : Type) where
  constructor MkLayout
  code : Bits64

||| The layout of the elements of an array of `a` (see `Layout`).  The
||| implementations other than the default one are those of this module, and
||| those that the compiler makes for records.
public export
interface Flat a where
  constructor MkFlat
  flatLayout : Layout a

||| Values: the layout of every type, unless it has another one.
%defaulthint
export
boxedFlat : Flat a
boxedFlat = MkFlat (MkLayout 0)

||| The code of a layout.
export
layoutCode : Layout a -> Bits64
layoutCode (MkLayout c) = c

||| The layout of a record of one constructor, with the tag `tag`, whose `n`
||| fields are all stored raw.  Only for the implementations that the
||| compiler makes: another layout would be read wrongly.
%unsafe
export
unsafeRecordLayout : (n : Bits64) -> (tag : Bits64) -> Layout a
unsafeRecordLayout n tag = MkLayout (2 + 256 * n + 16777216 * tag)

-- (the primitives: 1 + 256 * their number)
export
Flat Double where
  flatLayout = MkLayout 257

export
Flat Int where
  flatLayout = MkLayout 513

export
Flat Int64 where
  flatLayout = MkLayout 513

export
Flat Bits64 where
  flatLayout = MkLayout 769

export
Flat Int8 where
  flatLayout = MkLayout 1025

export
Flat Int16 where
  flatLayout = MkLayout 1281

export
Flat Int32 where
  flatLayout = MkLayout 1537

export
Flat Bits8 where
  flatLayout = MkLayout 1793

export
Flat Bits16 where
  flatLayout = MkLayout 2049

export
Flat Bits32 where
  flatLayout = MkLayout 2305

export
Flat Char where
  flatLayout = MkLayout 2561


-- The arrays of the slots of an `IOArray`, which hold `Maybe a`, by the
-- layout of `a` (see above): the RefC back end stores the
-- elements inline when the layout is not that of values, with a word that
-- tells whether the slot is empty.  The layout is the one that the caller
-- expects; the array's own one decides, so an array is read and written
-- correctly whatever layout the caller has (the default one, in code that is
-- generic in the type of the elements, say), only slower when they differ.
-- The other back ends ignore the layout: these are `prim__newArray`,
-- `prim__arrayGet` and `prim__arraySet`.
export %extern prim__newSlots : forall a . Layout a -> Int -> Maybe a -> PrimIO (ArrayData (Maybe a))
export %extern prim__slotGet : forall a . Layout a -> ArrayData (Maybe a) -> Int -> PrimIO (Maybe a)
export %extern prim__slotSet : forall a . Layout a -> ArrayData (Maybe a) -> Int -> Maybe a -> PrimIO ()
