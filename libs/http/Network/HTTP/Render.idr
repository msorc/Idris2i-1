||| HTTP/1.1 message heads as bytes (RFC 9112 sections 3, 4 and 5).
|||
||| The serialisers write what they are given: they do not check that the
||| method and the field names are tokens, or that the target, reason phrase
||| and field values have no CR or LF.  A program that puts text it did not
||| write itself in a head should check it first with `isValidHeaderName` and
||| `isValidHeaderValue` of `Network.HTTP.Types` (or `invalidHeader`), or a
||| CRLF in it lets the sender add fields or even messages.
module Network.HTTP.Render

import Data.ByteString
import Data.ByteString.Builder
import Data.ByteString.Internal
import Network.HTTP.Internal.Bytes
import Network.HTTP.Types

%default total

crlf : ByteString
crlf = "\r\n"

colonSpace : ByteString
colonSpace = ": "

httpSlash : ByteString
httpSlash = "HTTP/"

http11Space : ByteString
http11Space = "HTTP/1.1 "

spaceHttp11 : ByteString
spaceHttp11 = " HTTP/1.1\r\n"

-- A version as `HTTP/1.1`.
version : Version -> Builder
version v = byteString httpSlash <+> byteString (decimalBytes v.major) <+> word8 46
            <+> byteString (decimalBytes v.minor)

||| The field lines: `name: value` and CRLF for each field, in order (no
||| empty line after them).
export
renderHeaders : Headers -> Builder
renderHeaders hs = go (headersToListRev hs) neutral
  where
    -- (from the last field to the first, each before what follows it)
    go : List Header -> Builder -> Builder
    go [] acc = acc
    go (h :: rest) acc = go rest (byteString h.name <+> byteString colonSpace
                                  <+> byteString h.value <+> byteString crlf <+> acc)

||| The request line, the field lines and the empty line that ends the head.
export
renderRequestHead : RequestHead -> Builder
renderRequestHead r =
  byteString (methodBytes r.method) <+> word8 32 <+> byteString r.target
  <+> (if r.version == http11 then byteString spaceHttp11
       else word8 32 <+> version r.version <+> byteString crlf)
  <+> renderHeaders r.headers <+> byteString crlf

-- The three digits of a status code (100..999; others are written modulo
-- 1000, with leading zeros).
statusDigits : Int -> Builder
statusDigits c =
  let d2 = rem10 (quot10 (quot10 c))
      d1 = rem10 (quot10 c)
      d0 = rem10 c
  in word8 (cast (48 + d2)) <+> word8 (cast (48 + d1)) <+> word8 (cast (48 + d0))

||| The status line (`HTTP/1.1 200 OK`), the field lines and the empty line.
||| The reason phrase is the one of the status (see `statusFromCode`).
export
renderResponseHead : ResponseHead -> Builder
renderResponseHead r =
  (if r.version == http11 then byteString http11Space else version r.version <+> word8 32)
  <+> statusDigits r.status.code <+> word8 32 <+> byteString r.status.reason <+> byteString crlf
  <+> renderHeaders r.headers <+> byteString crlf
