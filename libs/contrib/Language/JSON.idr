||| The JSON language, as described at https://json.org/ and in RFC 8259.
|||
||| This module re-exports the type `JSON` (`Language.JSON.Data`) and the
||| parser of `Language.JSON.Parse`.  The other modules are
|||
|||  * `Language.JSON.Encode`: compact encoding into bytes;
|||  * `Language.JSON.Typed`: the interfaces `ToJSON` and `FromJSON`, to
|||    convert Idris values to and from JSON;
|||  * `Language.JSON.Derive`: implementations of these interfaces derived by
|||    elaborator reflection.
module Language.JSON

import Data.ByteString

import public Language.JSON.Data
import public Language.JSON.Parse

import public Text.Bounded

%default total

||| Parse a JSON text: `Nothing` if it is not one.  The parser is strict
||| (RFC 8259, see `Language.JSON.Parse`); `parseEither` says what is wrong.
export
parse : String -> Maybe JSON
parse x = case parseText x of
  Right j => Just j
  Left _ => Nothing

||| Parse a JSON text, or say where and why it is not one (the offset in the
||| error counts the bytes of the UTF-8 form of the string).
export
parseEither : String -> Either JSONError JSON
parseEither = parseText

||| Parse the bytes of a JSON text (UTF-8), or say where and why they are not
||| one.
export
parseByteString : ByteString -> Either JSONError JSON
parseByteString = parseBytes
