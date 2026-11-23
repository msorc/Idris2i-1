||| Incremental parsers of HTTP/1.1 message heads (RFC 9112), and the framing
||| of the body that follows a head.
|||
||| # Feeding a parser
|||
||| A connection loop makes a parser with `requestParser` (or
||| `responseParser`) and gives it the bytes as they arrive:
|||
||| ```idris
||| step : HeadParser RequestHead -> ByteString -> ...
||| step p chunk = case feed p chunk of
|||   NeedMore p'      => -- read more bytes and feed them to p'
|||   Done head rest   => -- `rest` is what follows the head: the body, or
|||                       -- the next pipelined request
|||   Failed err       => -- answer with `errorStatus err` and close
||| ```
|||
||| A head that arrives in one buffer is parsed in one pass over its bytes,
||| without copying: the method, target and the names and values of the
||| fields are slices of that buffer.  When a head arrives in pieces, the
||| complete lines of each piece are parsed at once, and only a line that is
||| split between pieces is copied (once, when its end arrives), so no byte
||| is examined more than twice whatever the sizes of the pieces.
|||
||| # Strictness
|||
||| The parser is strict where leniency has been used to smuggle requests
||| past a proxy that reads the message differently: it rejects whitespace
||| between a field name and the colon, obsolete line folding, a CR that is
||| not followed by LF, a line ended by LF alone, NUL and other control
||| characters in a field value, bytes that are not token characters in a
||| method or field name, and requests whose framing is ambiguous (see
||| `requestFraming`).  It enforces the size limits of a `Limits` record.
module Network.HTTP.Parser

import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal
import Data.List
import Data.Maybe
import Network.HTTP.Internal.Bytes
import Network.HTTP.Types

%default total

--------------------------------------------------------------------------
-- Limits and errors
--------------------------------------------------------------------------

||| Limits on what a parser accepts.  Lengths are in bytes and do not count
||| the CRLF that ends a line.
public export
record Limits where
  constructor MkLimits
  ||| The longest request line or status line.
  maxStartLine : Int
  ||| The longest header field line.
  maxHeaderLine : Int
  ||| The largest number of field lines.
  maxHeaders : Int
  ||| The largest head: start line, field lines and the empty line that ends
  ||| them, with all their CRLFs.
  maxHeadSize : Int
  ||| The largest `Content-Length` that `requestFraming` accepts (a larger
  ||| one is `ContentTooLarge`, 413); `Nothing` for no limit.  Bodies in
  ||| the chunked coding are not limited here: the decoder reports how much
  ||| it has produced.
  maxContentLength : Maybe Int

||| A request line of 8 KiB, 100 field lines of 8 KiB each, a head of 64 KiB
||| and no limit on the content length.
export
defaultLimits : Limits
defaultLimits = MkLimits 8192 8192 100 65536 Nothing

||| Why a head, or the framing of its body, was rejected.  `errorStatus`
||| gives the status code with which a server should answer.
public export
data HeadError
  = ||| The request line (or status line) is longer than `maxStartLine`.
    StartLineTooLong
  | ||| A field line is longer than `maxHeaderLine`.
    HeaderLineTooLong
  | ||| More than `maxHeaders` field lines.
    TooManyHeaders
  | ||| The head is larger than `maxHeadSize`.
    HeadTooLarge
  | ||| The request line does not have the form `method SP target SP version`.
    BadRequestLine
  | ||| The method is not a token.
    BadMethod
  | ||| The request target has a byte that is not visible ASCII.
    BadTarget
  | ||| The version is not `HTTP/` digit `.` digit.
    BadVersion
  | ||| The major version is not 1.
    UnsupportedVersion
  | ||| The status line does not have the form `version SP 3DIGIT SP reason`.
    BadStatusLine
  | ||| A field name is empty or has a byte that is not a token character.
    BadHeaderName
  | ||| Whitespace between a field name and the colon (RFC 9112 section 5.1).
    SpaceBeforeColon
  | ||| A field line without a colon.
    MissingColon
  | ||| A line that starts with whitespace: obsolete line folding (RFC 9112
    ||| section 5.2), or whitespace before the first field line.
    ObsFold
  | ||| A CR that is not followed by LF.
    BareCR
  | ||| A line ended by LF alone.
    BareLF
  | ||| A NUL byte in a field value.
    NulInHeader
  | ||| Another control character than horizontal tab in a field value.
    BadHeaderValue
  | ||| An HTTP/1.1 request without a `Host` field (RFC 9112 section 3.2).
    MissingHost
  | ||| A request with more than one `Host` field.
    DuplicateHost
  | ||| A `Content-Length` that is not a decimal number.
    BadContentLength
  | ||| `Content-Length` fields or list elements with different values.
    ConflictingContentLength
  | ||| Both `Content-Length` and `Transfer-Encoding`.
    ContentLengthAndTransferEncoding
  | ||| A request whose `Transfer-Encoding` does not end with `chunked`, or
    ||| has `chunked` more than once, or has an empty element.
    BadTransferEncoding
  | ||| A `Transfer-Encoding` with another coding than `chunked`.
    UnsupportedTransferCoding
  | ||| `Transfer-Encoding` in an HTTP/1.0 message (RFC 9112 section 6.1).
    TransferEncodingInHTTP10
  | ||| A `Content-Length` above `maxContentLength`.
    ContentTooLarge

||| The same error.
export
Eq HeadError where
  x == y = show' x == show' y
    where
      show' : HeadError -> Int
      show' StartLineTooLong = 0
      show' HeaderLineTooLong = 1
      show' TooManyHeaders = 2
      show' HeadTooLarge = 3
      show' BadRequestLine = 4
      show' BadMethod = 5
      show' BadTarget = 6
      show' BadVersion = 7
      show' UnsupportedVersion = 8
      show' BadStatusLine = 9
      show' BadHeaderName = 10
      show' SpaceBeforeColon = 11
      show' MissingColon = 12
      show' ObsFold = 13
      show' BareCR = 14
      show' BareLF = 15
      show' NulInHeader = 16
      show' BadHeaderValue = 17
      show' MissingHost = 18
      show' DuplicateHost = 19
      show' BadContentLength = 20
      show' ConflictingContentLength = 21
      show' ContentLengthAndTransferEncoding = 22
      show' BadTransferEncoding = 23
      show' UnsupportedTransferCoding = 24
      show' TransferEncodingInHTTP10 = 25
      show' ContentTooLarge = 26

||| The name of the constructor.
export
Show HeadError where
  show StartLineTooLong = "StartLineTooLong"
  show HeaderLineTooLong = "HeaderLineTooLong"
  show TooManyHeaders = "TooManyHeaders"
  show HeadTooLarge = "HeadTooLarge"
  show BadRequestLine = "BadRequestLine"
  show BadMethod = "BadMethod"
  show BadTarget = "BadTarget"
  show BadVersion = "BadVersion"
  show UnsupportedVersion = "UnsupportedVersion"
  show BadStatusLine = "BadStatusLine"
  show BadHeaderName = "BadHeaderName"
  show SpaceBeforeColon = "SpaceBeforeColon"
  show MissingColon = "MissingColon"
  show ObsFold = "ObsFold"
  show BareCR = "BareCR"
  show BareLF = "BareLF"
  show NulInHeader = "NulInHeader"
  show BadHeaderValue = "BadHeaderValue"
  show MissingHost = "MissingHost"
  show DuplicateHost = "DuplicateHost"
  show BadContentLength = "BadContentLength"
  show ConflictingContentLength = "ConflictingContentLength"
  show ContentLengthAndTransferEncoding = "ContentLengthAndTransferEncoding"
  show BadTransferEncoding = "BadTransferEncoding"
  show UnsupportedTransferCoding = "UnsupportedTransferCoding"
  show TransferEncodingInHTTP10 = "TransferEncodingInHTTP10"
  show ContentTooLarge = "ContentTooLarge"

||| The status code with which a server should answer a request that it
||| rejected for this reason: 414 for a long request line, 431 for fields
||| that are too large or too many, 413 for content that is too large, 505
||| for a major version other than 1, 501 for a transfer coding that is not
||| supported and 400 for the rest.  (A client that rejects a response has
||| nobody to answer; a proxy would answer 502.)
export
errorStatus : HeadError -> Int
errorStatus StartLineTooLong = 414
errorStatus HeaderLineTooLong = 431
errorStatus TooManyHeaders = 431
errorStatus HeadTooLarge = 431
errorStatus UnsupportedVersion = 505
errorStatus UnsupportedTransferCoding = 501
errorStatus ContentTooLarge = 413
errorStatus _ = 400

--------------------------------------------------------------------------
-- Parser state
--------------------------------------------------------------------------

-- What is being parsed, and what it gives.  (A constructor rather than a
-- function in the parser: a call of a function kept in a record goes
-- through its closure.)
data Kind : Type -> Type where
  ReqKind : Kind RequestHead
  RespKind : Kind ResponseHead
  TrailerKind : Kind Headers

-- The start line, once it has been parsed.
data StartLine
  = NoStart
  | ReqLine Method ByteString Version
  | StatusLine Version Status

||| The state of a parser of a head that produces an `a`: what it has parsed
||| of the head so far, and the bytes of the line that it has seen only part
||| of.  It is an immutable value: feeding it does not change it.
export
record HeadParser a where
  constructor MkHeadParser
  limits : Limits
  kind : Kind a
  start : StartLine
  -- The fields parsed so far, the last first, and how many.
  fieldsRev : List Header
  nfields : Int
  -- The bytes of the complete lines parsed so far.
  used : Int
  -- The pieces of the line that has not ended yet, the last first, and
  -- their total length.  The pieces never have an LF.
  pending : List ByteString
  pendingLen : Int

||| The result of feeding bytes to a parser.
public export
data Progress : Type -> Type where
  ||| The head has not ended: feed the next bytes to this parser.
  NeedMore : HeadParser a -> Progress a
  ||| The head, and the bytes that follow it (a slice of the input).
  Done : a -> (rest : ByteString) -> Progress a
  ||| The head is not valid, or is beyond the limits.
  Failed : HeadError -> Progress a

--------------------------------------------------------------------------
-- Byte-level scanning (absolute offsets in a buffer)
--------------------------------------------------------------------------

-- (The index is passed as `i + 0`, a new value, so that the loops that
-- call this keep `i` in a C integer: with the RefC back end, a variable
-- that a foreign function takes is kept as a value.)
%inline
at : Buffer -> Int -> Bits8
at b i = unsafeBufferByte b (i + 0)

-- The scanners below read four bytes at a time while at least four are
-- left, and then one at a time; a word with a byte that may end the run is
-- looked at byte by byte.

%inline
word : Buffer -> Int -> Bits32
word b i = unsafeBufferWord32LE b (i + 0)

%inline
byteOf : Bits32 -> Bits32 -> Bits8
byteOf w k = cast (prim__shr_Bits32 w k)

-- The first index in [i, e) whose byte is not a token character, or e.
scanToken1 : Buffer -> Int -> Int -> Int
scanToken1 b i e = if i < e && isTChar (at b i) then scanToken1 b (assert_smaller i (i + 1)) e else i

scanToken : Buffer -> Int -> Int -> Int
scanToken b i e =
  if i + 4 <= e
     then let w = word b i in
          if isTChar (byteOf w 0) && isTChar (byteOf w 8) && isTChar (byteOf w 16) && isTChar (byteOf w 24)
             then scanToken b (assert_smaller i (i + 4)) e
             else scanToken1 b i e
     else scanToken1 b i e

-- The first index in [i, e) whose byte is not a field value character.
scanValue1 : Buffer -> Int -> Int -> Int
scanValue1 b i e = if i < e && isFieldVChar (at b i) then scanValue1 b (assert_smaller i (i + 1)) e else i

scanValue : Buffer -> Int -> Int -> Int
scanValue b i e =
  if i + 4 <= e
     then let w = word b i in
          -- (a tab is below 0x20: its word is looked at byte by byte)
          if hasByteBelow w 0x20 || hasByteEq w 0x7F
             then let j = scanValue1 b i (i + 4) in
                  if j == i + 4 then scanValue b (assert_smaller i j) e else j
             else scanValue b (assert_smaller i (i + 4)) e
     else scanValue1 b i e

-- The first index in [i, e) whose byte is not visible ASCII (0x21..0x7E).
scanTarget1 : Buffer -> Int -> Int -> Int
scanTarget1 b i e =
  if i < e then let w = at b i in
                if w > 0x20 && w < 0x7F then scanTarget1 b (assert_smaller i (i + 1)) e else i
  else i

scanTarget : Buffer -> Int -> Int -> Int
scanTarget b i e =
  if i + 4 <= e
     then let w = word b i in
          if hasByteBelow w 0x21 || hasHighByte w || hasByteEq w 0x7F
             then scanTarget1 b i e
             else scanTarget b (assert_smaller i (i + 4)) e
     else scanTarget1 b i e

-- The first index in [i, e) whose byte is not a space or tab.
skipOWS : Buffer -> Int -> Int -> Int
skipOWS b i e = if i < e && isOWS (at b i) then skipOWS b (assert_smaller i (i + 1)) e else i

-- The index after the last byte of [s, p) that is not a space or tab.
trimBack : Buffer -> Int -> Int -> Int
trimBack b s p = if p > s && isOWS (at b (p - 1)) then trimBack b s (assert_smaller p (p - 1)) else p

-- Is there an LF in [i, e)?
hasLF : Buffer -> Int -> Int -> Bool
hasLF b i e = if i >= e then False else if at b i == 10 then True else hasLF b (assert_smaller i (i + 1)) e

-- The method of the token in [s, m), without allocating for the methods
-- that have a constructor.
methodAt : Buffer -> Int -> Int -> Method
methodAt b s m =
  let n = m - s
      c0 = at b s
  in case n of
       3 => if c0 == 0x47 && at b (s + 1) == 0x45 && at b (s + 2) == 0x54 then GET
            else if c0 == 0x50 && at b (s + 1) == 0x55 && at b (s + 2) == 0x54 then PUT
            else other
       4 => if c0 == 0x50 && at b (s + 1) == 0x4F && at b (s + 2) == 0x53 && at b (s + 3) == 0x54 then POST
            else if c0 == 0x48 && at b (s + 1) == 0x45 && at b (s + 2) == 0x41 && at b (s + 3) == 0x44 then HEAD
            else other
       _ => other
  where
    other : Method
    other = methodFromBytes (UnsafeBS b s (m - s))

-- The version `HTTP/d.d` at s (8 bytes, which must be available), as
-- ten times the major digit and the minor digit, or -1 for a malformed one
-- (a number rather than a `Maybe`, which would be allocated); the major
-- version is checked by the caller.
versionAt : Buffer -> Int -> Int
versionAt b s =
  if at b s == 0x48 && at b (s + 1) == 0x54 && at b (s + 2) == 0x54 && at b (s + 3) == 0x50
     && at b (s + 4) == 0x2F && isDigit (at b (s + 5)) && at b (s + 6) == 0x2E
     && isDigit (at b (s + 7))
     then (cast {to = Int} (at b (s + 5)) - 48) * 10 + (cast {to = Int} (at b (s + 7)) - 48)
     else -1

-- The version of a number of `versionAt`.
versionOf : Int -> Version
versionOf 11 = http11
versionOf 10 = http10
versionOf n = MkVersion (quot10 n) (rem10 n)

--------------------------------------------------------------------------
-- The parser
--------------------------------------------------------------------------

-- Count the fields named `host`.
countHost : List Header -> Int -> Int
countHost [] k = k
countHost (h :: hs) k = countHost hs (if eqLower h.name hHost then k + 1 else k)

finishRequest : StartLine -> List Header -> Either HeadError RequestHead
finishRequest (ReqLine m t v) acc =
  let hosts = countHost acc 0 in
  if hosts > 1 then Left DuplicateHost
  else if hosts == 0 && v.minor >= 1 then Left MissingHost
  else Right (MkRequestHead m t v (headersFromListRev acc))
finishRequest _ _ = Left BadRequestLine

finishResponse : StartLine -> List Header -> Either HeadError ResponseHead
finishResponse (StatusLine v s) acc = Right (MkResponseHead v s (headersFromListRev acc))
finishResponse _ _ = Left BadStatusLine

finishTrailer : StartLine -> List Header -> Either HeadError Headers
finishTrailer _ acc = Right (headersFromListRev acc)

-- Make the result of a parser from the start line and the fields (the
-- last first).
finish : Kind a -> StartLine -> List Header -> Either HeadError a
finish ReqKind = finishRequest
finish RespKind = finishResponse
finish TrailerKind = finishTrailer

-- The parser after a line that has not ended: the bytes [i, e) of `b`.
incomplete : HeadParser a -> StartLine -> List Header -> (n, used : Int) -> Buffer -> (i, e : Int) -> Progress a
incomplete p start acc n used b i e =
  let len = e - i
      maxLine = case start of
                     NoStart => case p.kind of
                                     TrailerKind => p.limits.maxHeaderLine
                                     _ => p.limits.maxStartLine
                     _ => p.limits.maxHeaderLine
  in if len > maxLine + 1
        then Failed (case start of
                          NoStart => case p.kind of
                                          TrailerKind => HeaderLineTooLong
                                          _ => StartLineTooLong
                          _ => HeaderLineTooLong)
     else if used + len > p.limits.maxHeadSize then Failed HeadTooLarge
     else NeedMore ({ start := start, fieldsRev := acc, nfields := n, used := used,
                      pending := if len == 0 then [] else [UnsafeBS b i len],
                      pendingLen := len } p)

-- Parse field lines from i (the start of a line) in the bytes [.., e) of b.
-- The limits are passed as numbers, which the loop keeps in C integers.
fieldsL : HeadParser a -> StartLine -> (maxLine, maxN, maxSize : Int) -> Buffer -> (i, e : Int) -> List Header -> (n, used : Int) -> Progress a
fieldsL p start maxLine maxN maxSize b i e acc n used =
  if i >= e then incomplete p start acc n used b i e else
  let c = at b i in
  if c == 13
     then if i + 1 >= e then incomplete p start acc n used b i e
          else if at b (i + 1) == 10
                  then let used' = used + 2 in
                       if used' > maxSize then Failed HeadTooLarge
                       else case finish p.kind start acc of
                              Left err => Failed err
                              Right r => Done r (UnsafeBS b (i + 2) (e - i - 2))
                  else Failed BareCR
  else if c == 10 then Failed BareLF
  else if isOWS c then Failed ObsFold
  else
  let q = scanToken b i e in
  if q >= e then incomplete p start acc n used b i e else
  let cq = at b q in
  if cq /= 0x3A
     then Failed (if q == i then BadHeaderName
                  else if isOWS cq then SpaceBeforeColon
                  else if cq == 13 || cq == 10 then MissingColon
                  else BadHeaderName)
  else if q == i then Failed BadHeaderName
  else
  let vs = skipOWS b (q + 1) e
      ve = scanValue b vs e
  in if ve >= e then incomplete p start acc n used b i e else
     let cv = at b ve in
     if cv == 13
        then if ve + 1 >= e then incomplete p start acc n used b i e
             else if at b (ve + 1) /= 10 then Failed BareCR
             else let next = ve + 2
                      used' = used + (next - i)
                  in if ve - i > maxLine then Failed HeaderLineTooLong
                     else if n >= maxN then Failed TooManyHeaders
                     else if used' > maxSize then Failed HeadTooLarge
                     else let vend = trimBack b vs ve
                              h = MkHeader (UnsafeBS b i (q - i)) (UnsafeBS b vs (vend - vs))
                          in fieldsL p start maxLine maxN maxSize b (assert_smaller i next) e (h :: acc) (n + 1) used'
     else Failed (if cv == 10 then BareLF else if cv == 0 then NulInHeader else BadHeaderValue)

fields : HeadParser a -> StartLine -> Buffer -> (i, e : Int) -> List Header -> (n, used : Int) -> Progress a
fields p start = fieldsL p start p.limits.maxHeaderLine p.limits.maxHeaders p.limits.maxHeadSize

-- Parse a request line from i.
requestLine : HeadParser a -> Buffer -> (i, e : Int) -> (used : Int) -> Progress a
requestLine p b i e used =
  if i >= e then incomplete p NoStart [] 0 used b i e else
  let c = at b i in
  -- Empty lines before the request line are ignored (RFC 9112 section 2.2).
  if c == 13
     then if i + 1 >= e then incomplete p NoStart [] 0 used b i e
          else if at b (i + 1) == 10
                  then if used + 2 > p.limits.maxHeadSize then Failed HeadTooLarge
                       else requestLine p b (assert_smaller i (i + 2)) e (used + 2)
                  else Failed BareCR
  else if c == 10 then Failed BareLF
  else
  let m = scanToken b i e in
  if m >= e then incomplete p NoStart [] 0 used b i e
  else if m == i then Failed (if c == 32 then BadRequestLine else BadMethod)
  else if at b m /= 32 then Failed (let x = at b m in if x == 13 || x == 10 then BadRequestLine else BadMethod)
  else
  let ts = m + 1
      t = scanTarget b ts e
  in if t >= e then incomplete p NoStart [] 0 used b i e
     else if t == ts then Failed BadRequestLine
     else let ct = at b t in
     if ct /= 32 then Failed (if ct == 13 || ct == 10 then BadRequestLine else BadTarget)
     else
     let vs = t + 1 in
     -- (whether the line ends before the version does is decided from the
     -- bytes of the line only, so that the result does not depend on how
     -- the input was split)
     if vs + 9 > e
        then if hasLF b vs e then Failed BadVersion else incomplete p NoStart [] 0 used b i e
     else let vn = versionAt b vs in
       if vn < 0 then Failed BadVersion else
         let v = versionOf vn in
         if at b (vs + 8) /= 13 then Failed (if at b (vs + 8) == 10 then BareLF else BadVersion)
         else if vs + 10 > e then incomplete p NoStart [] 0 used b i e
         else if at b (vs + 9) /= 10 then Failed BareCR
         else if vs + 8 - i > p.limits.maxStartLine then Failed StartLineTooLong
         else if v.major /= 1 then Failed UnsupportedVersion
         else let next = vs + 10
                  used' = used + (next - i)
              in if used' > p.limits.maxHeadSize then Failed HeadTooLarge
                 else fields p (ReqLine (methodAt b i m) (UnsafeBS b ts (t - ts)) v)
                             b next e [] 0 used'

-- Parse a status line from i.
statusLine : HeadParser a -> Buffer -> (i, e : Int) -> (used : Int) -> Progress a
statusLine p b i e used =
  if i + 13 > e
     then if hasLF b i e then Failed BadStatusLine else incomplete p NoStart [] 0 used b i e
  else let vn = versionAt b i in
    if vn < 0 then Failed BadStatusLine else
      let v = versionOf vn
          d0 = at b (i + 9)
          d1 = at b (i + 10)
          d2 = at b (i + 11)
      in if at b (i + 8) /= 32 || not (isDigit d0 && isDigit d1 && isDigit d2) || d0 == 48
            then Failed BadStatusLine
         else if v.major /= 1 then Failed UnsupportedVersion
         else
         let code : Int
             code = (cast d0 - 48) * 100 + (cast d1 - 48) * 10 + (cast d2 - 48)
             c12 = at b (i + 12)
             -- The reason phrase may be absent, with or without its space.
             rs = if c12 == 32 then i + 13 else i + 12
             re = scanValue b rs e
         in if c12 /= 32 && c12 /= 13 then Failed (if c12 == 10 then BareLF else BadStatusLine)
            else if re >= e then incomplete p NoStart [] 0 used b i e
            else let cr = at b re in
            if cr /= 13 then Failed (if cr == 10 then BareLF else if rs == i + 12 then BadStatusLine else BadHeaderValue)
            else if re + 1 >= e then incomplete p NoStart [] 0 used b i e
            else if at b (re + 1) /= 10 then Failed BareCR
            else if re - i > p.limits.maxStartLine then Failed StartLineTooLong
            else let next = re + 2
                     used' = used + (next - i)
                     reason = UnsafeBS b rs (trimBack b rs re - rs)
                 in if used' > p.limits.maxHeadSize then Failed HeadTooLarge
                    else fields p (StatusLine v (MkStatus code reason))
                                b next e [] 0 used'

-- Parse the contiguous bytes of a byte string with a parser that has
-- nothing pending.
run : HeadParser a -> ByteString -> Progress a
run p (UnsafeBS b o n) =
  let e = o + n in
  case p.start of
    NoStart => case p.kind of
                 ReqKind => requestLine p b o e p.used
                 RespKind => statusLine p b o e p.used
                 TrailerKind => fields p NoStart b o e p.fieldsRev p.nfields p.used
    st => fields p st b o e p.fieldsRev p.nfields p.used

||| Give the next bytes of the input to a parser.  Bytes that come after the
||| end of the head are returned with `Done`, untouched; feeding an empty
||| byte string gives `NeedMore` with the same state.
export
feed : HeadParser a -> ByteString -> Progress a
feed p chunk =
  if p.pendingLen == 0 then run p chunk else
  let j = findByteFrom 10 0 chunk in
  if j < 0
     then let UnsafeBS b o n = chunk in
          if n == 0 then NeedMore p
          else -- Still no end of line: keep the piece and check the limits.
               let len = p.pendingLen + n
                   maxLine = case p.start of
                                  NoStart => case p.kind of
                                                  TrailerKind => p.limits.maxHeaderLine
                                                  _ => p.limits.maxStartLine
                                  _ => p.limits.maxHeaderLine
               in if len > maxLine + 1
                     then Failed (case p.start of
                                       NoStart => case p.kind of
                                                       TrailerKind => HeaderLineTooLong
                                                       _ => StartLineTooLong
                                       _ => HeaderLineTooLong)
                  else if p.used + len > p.limits.maxHeadSize then Failed HeadTooLarge
                  else NeedMore ({ pending := chunk :: p.pending, pendingLen := len } p)
     else -- The line ends in this piece: parse it whole, then the rest.
          let line = Data.ByteString.concat (reverse (takeInt (j + 1) chunk :: p.pending))
              rest = dropInt (j + 1) chunk
          in case run ({ pending := [], pendingLen := 0 } p) line of
               NeedMore p' => assert_total (feed p' rest)
               Done r _ => Done r rest
               Failed err => Failed err

||| A parser of a request head: the request line and the field lines, up to
||| and including the empty line.  It checks the `Host` rule of RFC 9112
||| section 3.2 (exactly one in HTTP/1.1, at most one in HTTP/1.0), and does
||| not look at the other fields: see `requestFraming`.
export
requestParser : Limits -> HeadParser RequestHead
requestParser l = MkHeadParser l ReqKind NoStart [] 0 0 [] 0

||| A parser of a response head.  The status line may lack the reason phrase
||| (`HTTP/1.1 200` and `HTTP/1.1 200 ` are accepted).
export
responseParser : Limits -> HeadParser ResponseHead
responseParser l = MkHeadParser l RespKind NoStart [] 0 0 [] 0

||| A parser of field lines up to the empty line that ends them, with no
||| start line: the trailer section of a chunked body (used by
||| `Network.HTTP.Chunked`).  The limits on the start line do not apply.
export
fieldsParser : Limits -> HeadParser Headers
fieldsParser l = MkHeadParser l TrailerKind NoStart [] 0 0 [] 0

||| How many bytes of the head the parser has consumed so far (complete
||| lines and the start of the line that has not ended).
export
consumed : HeadParser a -> Int
consumed p = p.used + p.pendingLen

||| Parse a request head from bytes, as `feed (requestParser l)`.
export
parseRequestHead : Limits -> ByteString -> Progress RequestHead
parseRequestHead l = feed (requestParser l)

||| Parse a response head from bytes, as `feed (responseParser l)`.
export
parseResponseHead : Limits -> ByteString -> Progress ResponseHead
parseResponseHead l = feed (responseParser l)

--------------------------------------------------------------------------
-- Body framing (RFC 9112 section 6)
--------------------------------------------------------------------------

||| How the body of a message is delimited.
public export
data BodyFraming
  = ||| There is no body (the next message follows the head).
    NoBody
  | ||| The body is this many bytes.
    ContentLength Int
  | ||| The body is in the chunked transfer coding (`Network.HTTP.Chunked`).
    Chunked
  | ||| The body is everything until the connection closes (responses only).
    UntilClose

||| The same framing.
export
Eq BodyFraming where
  NoBody == NoBody = True
  ContentLength a == ContentLength b = a == b
  Chunked == Chunked = True
  UntilClose == UntilClose = True
  _ == _ = False

||| As the constructor.
export
Show BodyFraming where
  show NoBody = "NoBody"
  show (ContentLength n) = "ContentLength " ++ show n
  show Chunked = "Chunked"
  show UntilClose = "UntilClose"

-- The elements of a comma-separated list, trimmed of whitespace, in
-- order, empty ones included, appended in reverse to `acc`.
listElems : ByteString -> List ByteString -> List ByteString
listElems v acc = go 0 0 acc
  where
    go : Int -> Int -> List ByteString -> List ByteString
    go s i acc =
      if i >= lengthInt v then trimOWS (sliceFromTo s i v) :: acc
      else if unsafeIndex v i == 44
              then go (i + 1) (assert_smaller i (i + 1)) (trimOWS (sliceFromTo s i v) :: acc)
              else go s (assert_smaller i (i + 1)) acc

-- All the list elements of the fields with a name, the last first, from
-- the fields the last first.
elemsOf : ByteString -> List Header -> List ByteString
elemsOf n [] = []
elemsOf n (h :: hs) = if eqLower h.name n then listElems h.value [] ++ elemsOf n hs else elemsOf n hs

-- The content length of the fields, if there is a `Content-Length`: every
-- field and list element must be the same number (RFC 9110 section 8.6).
contentLength : List Header -> Maybe (Either HeadError Int)
contentLength hs =
  case elemsOf hContentLength hs of
    [] => Nothing
    (x :: xs) => let n = parseDecimal x in
                 if n < 0 then Just (Left BadContentLength)
                 else Just (same n xs)
  where
    same : Int -> List ByteString -> Either HeadError Int
    same n [] = Right n
    same n (y :: ys) = let m = parseDecimal y in
                       if m < 0 then Left BadContentLength
                       else if m /= n then Left ConflictingContentLength
                       else same n ys

chunkedBS : ByteString
chunkedBS = "chunked"

data TECheck = TEChunked | TENotChunked | TEBad | TEUnsupported

-- Check the transfer codings (the last first): `chunked` must be the
-- last, and only once; any other coding is not supported.
checkCodings : List ByteString -> TECheck
checkCodings [] = TEBad
checkCodings (lst :: others) =
  if lengthInt lst == 0 then TEBad
  else if eqLower lst chunkedBS
          then checkOthers others
          else if any (\x => lengthInt x == 0) others then TEBad else TENotChunked
  where
    checkOthers : List ByteString -> TECheck
    checkOthers [] = TEChunked
    checkOthers (x :: xs) =
      if lengthInt x == 0 || eqLower x chunkedBS then TEBad else
      case checkOthers xs of
        TEBad => TEBad
        _ => TEUnsupported

||| The framing of the body of a request (RFC 9112 section 6.3), or why the
||| request must be rejected:
|||
|||  * `Transfer-Encoding` and `Content-Length` together are rejected
|||    (`ContentLengthAndTransferEncoding`): RFC 9112 allows a server to
|||    process such a request, but they are the shape of a request smuggling
|||    attack.
|||  * `Transfer-Encoding` must be `chunked` (several fields and list elements
|||    are joined): one whose last coding is not `chunked`, or with `chunked`
|||    twice, is `BadTransferEncoding`; other codings before `chunked` are
|||    `UnsupportedTransferCoding` (501).  In an HTTP/1.0 request it is
|||    `TransferEncodingInHTTP10`.
|||  * `Content-Length` must be a decimal number; several fields or list
|||    elements must all have the same value; above `maxContentLength` it is
|||    `ContentTooLarge`.
|||  * Otherwise there is no body.
export
requestFraming : Limits -> RequestHead -> Either HeadError BodyFraming
requestFraming l r =
  let hs = headersToListRev r.headers in
  case elemsOf hTransferEncoding hs of
    tes@(_ :: _) =>
      if r.version.minor == 0 then Left TransferEncodingInHTTP10
      else if isJust (contentLength hs) then Left ContentLengthAndTransferEncoding
      else case checkCodings tes of
             TEChunked => Right Chunked
             TEUnsupported => Left UnsupportedTransferCoding
             _ => Left BadTransferEncoding
    [] => case contentLength hs of
            Nothing => Right NoBody
            Just (Left err) => Left err
            Just (Right n) => case l.maxContentLength of
                                Just m => if n > m then Left ContentTooLarge else Right (ContentLength n)
                                Nothing => Right (ContentLength n)

||| The framing of the body of a response to a request with a method
||| (RFC 9112 section 6.3):
|||
|||  * no body for a response to `HEAD`, a 1xx, 204 or 304 response, and a
|||    2xx response to `CONNECT` (after which the connection is a tunnel);
|||  * `Transfer-Encoding` whose last coding is `chunked` is `Chunked` (other
|||    codings before it are `UnsupportedTransferCoding`), and one whose
|||    last coding is not is `UntilClose`; with a `Content-Length` too, or in
|||    an HTTP/1.0 response, it is an error (RFC 9112 lets the
|||    `Transfer-Encoding` win, and says that such a message "ought to be
|||    handled as an error");
|||  * a valid `Content-Length` is the length, and an invalid one an error;
|||  * otherwise the body runs until the connection closes.
export
responseFraming : (requestMethod : Method) -> ResponseHead -> Either HeadError BodyFraming
responseFraming m r =
  let c = r.status.code
      hs = headersToListRev r.headers
  in if m == HEAD || (c >= 100 && c < 200) || c == 204 || c == 304 then Right NoBody
     else if m == CONNECT && c >= 200 && c < 300 then Right NoBody
     else case elemsOf hTransferEncoding hs of
            tes@(_ :: _) =>
              if r.version.minor == 0 then Left TransferEncodingInHTTP10
              else if isJust (contentLength hs) then Left ContentLengthAndTransferEncoding
              else case checkCodings tes of
                     TEChunked => Right Chunked
                     TEUnsupported => Left UnsupportedTransferCoding
                     TENotChunked => Right UntilClose
                     TEBad => Left BadTransferEncoding
            [] => case contentLength hs of
                    Nothing => Right UntilClose
                    Just (Left err) => Left err
                    Just (Right n) => Right (ContentLength n)

closeBS : ByteString
closeBS = "close"

keepAliveBS : ByteString
keepAliveBS = "keep-alive"

continueBS : ByteString
continueBS = "100-continue"

||| Does the connection stay open after a message with this version and
||| these fields (RFC 9112 section 9.3)?  Not if `Connection` has `close`;
||| otherwise yes for HTTP/1.1 and later, and for HTTP/1.0 only if
||| `Connection` has `keep-alive`.
export
isPersistent : Version -> Headers -> Bool
isPersistent v hs =
  if headerHasToken hConnection closeBS hs then False
  else if v.minor >= 1 then True
  else headerHasToken hConnection keepAliveBS hs

||| Does the request ask for a `100 Continue` before it sends its body
||| (`Expect: 100-continue`, RFC 9110 section 10.1.1)?
export
expectsContinue : RequestHead -> Bool
expectsContinue r = case lookupHeader hExpect r.headers of
                         Just v => eqLower v continueBS
                         Nothing => False
