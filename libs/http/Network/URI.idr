||| URIs (RFC 3986) and the request targets of HTTP/1.1 (RFC 9112 section
||| 3.2).
|||
||| A parsed URI keeps its components as they were written, percent-encoded
||| (slices of the input): decoding is a separate step (`percentDecode`),
||| because a `/` or `?` that was written `%2F` or `%3F` is data, not a
||| delimiter, and must not become one.  The parsers check every byte of
||| every component against the grammar of RFC 3986 appendix A, including
||| `%` followed by two hexadecimal digits.
|||
|||  * `parseURI`, `parseURIReference`, `renderURI`: URIs and references.
|||  * `parseRequestTarget`: the four forms of a request target.
|||  * `percentDecode`, `percentEncode` and the encoders of each component.
|||  * `parseQuery`, `formEncode`: `application/x-www-form-urlencoded`.
|||  * `removeDotSegments` (path normalisation) and `resolve` (references
|||    against a base, RFC 3986 section 5).
module Network.URI

import Data.Bits
import Data.Buffer
import Data.ByteString
import Data.ByteString.Builder
import Data.ByteString.Internal
import Data.List
import Data.Maybe
import Network.HTTP.Internal.Bytes
import Network.HTTP.Types

%default total

--------------------------------------------------------------------------
-- Character classes (RFC 3986 section 2 and appendix A)
--------------------------------------------------------------------------

-- Is the byte in the set given by masks of the codes 0..63 and 64..127?
%inline
inSet : Bits64 -> Bits64 -> Bits8 -> Bool
inSet lo hi w = if w < 64 then maskHas lo w else if w < 128 then maskHas hi (w - 64) else False

-- The masks of the sets (computed from the grammar).
%inline
unreservedLo, unreservedHi, regNameLo, regNameHi, userinfoLo, userinfoHi : Bits64
unreservedLo = 0x03FF600000000000
unreservedHi = 0x47FFFFFE87FFFFFE
regNameLo = 0x2BFF7FD200000000
regNameHi = 0x47FFFFFE87FFFFFE
userinfoLo = 0x2FFF7FD200000000
userinfoHi = 0x47FFFFFE87FFFFFE

%inline
pcharLo, pcharHi, pathLo, pathHi, queryLo, queryHi, schemeLo, schemeHi, formLo, formHi : Bits64
pcharLo = 0x2FFF7FD200000000
pcharHi = 0x47FFFFFE87FFFFFF
pathLo = 0x2FFFFFD200000000
pathHi = 0x47FFFFFE87FFFFFF
queryLo = 0xAFFFFFD200000000
queryHi = 0x47FFFFFE87FFFFFF
schemeLo = 0x03FF680000000000
schemeHi = 0x07FFFFFE07FFFFFE
formLo = 0x03FF640000000000
formHi = 0x07FFFFFE87FFFFFE

||| `unreserved`: letters, digits, `-`, `.`, `_` and `~`.
export
isUnreserved : Bits8 -> Bool
isUnreserved = inSet unreservedLo unreservedHi

||| `sub-delims`: ``!$&'()*+,;=``.
export
isSubDelim : Bits8 -> Bool
isSubDelim w = inSet regNameLo regNameHi w && not (isUnreserved w)

||| `pchar` without `%`: what may be written as it is in a path segment.
export
isPChar : Bits8 -> Bool
isPChar = inSet pcharLo pcharHi

isAlpha : Bits8 -> Bool
isAlpha w = (w >= 65 && w <= 90) || (w >= 97 && w <= 122)

-- Are the bytes [s, e) of bs in the set, or `%` and two hexadecimal digits?
validIn : Bits64 -> Bits64 -> ByteString -> Int -> Int -> Bool
validIn lo hi bs s e =
  if s >= e then True
  else let w = unsafeIndex bs s in
       if w == 37
          then if s + 2 < e && hexValue (unsafeIndex bs (s + 1)) >= 0 && hexValue (unsafeIndex bs (s + 2)) >= 0
                  then validIn lo hi bs (assert_smaller s (s + 3)) e
                  else False
          else if inSet lo hi w then validIn lo hi bs (assert_smaller s (s + 1)) e else False

-- The whole byte string.
validAll : Bits64 -> Bits64 -> ByteString -> Bool
validAll lo hi bs = validIn lo hi bs 0 (lengthInt bs)

-- The first index in [s, e) of a byte for which the predicate holds, or e.
findFrom : (Bits8 -> Bool) -> ByteString -> Int -> Int -> Int
findFrom p bs s e = if s >= e then e else if p (unsafeIndex bs s) then s else findFrom p bs (assert_smaller s (s + 1)) e

-- The last index in [s, e) of a byte, or -1.
lastIndexOf : Bits8 -> ByteString -> Int -> Int -> Int
lastIndexOf w bs s e = if e <= s then -1 else if unsafeIndex bs (e - 1) == w then e - 1 else lastIndexOf w bs s (assert_smaller e (e - 1))

--------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------

||| The host of an authority.
public export
data Host
  = ||| A registered name (a DNS name usually), as written: may be
    ||| percent-encoded, and is case-insensitive.
    RegName ByteString
  | ||| A dotted-decimal IPv4 address.
    IPv4 ByteString
  | ||| An IPv6 address: the text between the brackets.
    IPv6 ByteString
  | ||| An `IPvFuture` literal: the text between the brackets (`v1.x`).
    IPFuture ByteString

||| The same constructor and bytes.
export
Eq Host where
  RegName a == RegName b = a == b
  IPv4 a == IPv4 b = a == b
  IPv6 a == IPv6 b = a == b
  IPFuture a == IPFuture b = a == b
  _ == _ = False

||| As the constructor and the text.
export
Show Host where
  show (RegName h) = "RegName " ++ show h
  show (IPv4 h) = "IPv4 " ++ show h
  show (IPv6 h) = "IPv6 " ++ show h
  show (IPFuture h) = "IPFuture " ++ show h

||| The authority of a URI: `[userinfo "@"] host [":" port]`.
public export
record Authority where
  constructor MkAuthority
  ||| As written (percent-encoded), without the `@`.
  userinfo : Maybe ByteString
  host : Host
  ||| `Nothing` if there is no port or the port is empty (`host:`).
  port : Maybe Int

||| The same components.
export
Eq Authority where
  x == y = x.userinfo == y.userinfo && x.host == y.host && x.port == y.port

||| As a record, for tests.
export
Show Authority where
  show a = "MkAuthority " ++ show a.userinfo ++ " (" ++ show a.host ++ ") " ++ show a.port

||| A URI reference.  A URI has a scheme; a relative reference has none.
||| The components are as written (percent-encoded), without their
||| delimiters (`:`, `//`, `?`, `#`).
public export
record URI where
  constructor MkURI
  scheme : Maybe ByteString
  authority : Maybe Authority
  ||| May be empty.
  path : ByteString
  query : Maybe ByteString
  fragment : Maybe ByteString

||| The same components (the scheme and host are compared as written).
export
Eq URI where
  x == y = x.scheme == y.scheme && x.authority == y.authority && x.path == y.path
           && x.query == y.query && x.fragment == y.fragment

||| Why a URI or request target was rejected.
public export
data URIError
  = ||| The scheme does not start with a letter or has a byte that is not a
    ||| letter, digit, `+`, `-` or `.`; or there is no scheme where one is
    ||| needed.
    BadScheme
  | BadUserinfo
  | ||| Not a registered name, IPv4 address or bracketed IP literal.
    BadHost
  | ||| Not digits, or above 65535.
    BadPort
  | ||| A byte that is not allowed in a path, or a path that cannot follow
    ||| what is before it (`//` without an authority, or a relative path
    ||| after one).
    BadPath
  | BadQuery
  | BadFragment
  | ||| A request target that does not have the form that the method needs.
    BadTargetForm

||| The same error.
export
Eq URIError where
  BadScheme == BadScheme = True
  BadUserinfo == BadUserinfo = True
  BadHost == BadHost = True
  BadPort == BadPort = True
  BadPath == BadPath = True
  BadQuery == BadQuery = True
  BadFragment == BadFragment = True
  BadTargetForm == BadTargetForm = True
  _ == _ = False

||| The constructor.
export
Show URIError where
  show BadScheme = "BadScheme"
  show BadUserinfo = "BadUserinfo"
  show BadHost = "BadHost"
  show BadPort = "BadPort"
  show BadPath = "BadPath"
  show BadQuery = "BadQuery"
  show BadFragment = "BadFragment"
  show BadTargetForm = "BadTargetForm"

--------------------------------------------------------------------------
-- Hosts
--------------------------------------------------------------------------

-- A `dec-octet` in [s, e): 0..255 without leading zeros.
decOctet : ByteString -> Int -> Int -> Bool
decOctet bs s e =
  let n = e - s in
  if n < 1 || n > 3 then False
  else if not (all' s) then False
  else if n > 1 && unsafeIndex bs s == 48 then False
  else parseDecimal (sliceFromTo s e bs) <= 255
  where
    all' : Int -> Bool
    all' i = if i >= e then True else if isDigit (unsafeIndex bs i) then all' (assert_smaller i (i + 1)) else False

-- An IPv4 address in [s, e): four dec-octets separated by dots.
ipv4In : ByteString -> Int -> Int -> Bool
ipv4In bs s e = go s 0
  where
    go : Int -> Int -> Bool
    go i k =
      let j = findFrom (== 46) bs i e in
      if k == 3 then j == e && decOctet bs i e
      else j < e && decOctet bs i j && go (assert_smaller i (j + 1)) (k + 1)

||| Is it a dotted-decimal IPv4 address (`IPv4address` of RFC 3986)?
export
isIPv4 : ByteString -> Bool
isIPv4 bs = ipv4In bs 0 (lengthInt bs)

-- 1 to 4 hexadecimal digits in [s, e).
h16 : ByteString -> Int -> Int -> Bool
h16 bs s e = let n = e - s in n >= 1 && n <= 4 && go s
  where
    go : Int -> Bool
    go i = if i >= e then True else if hexValue (unsafeIndex bs i) >= 0 then go (assert_smaller i (i + 1)) else False

-- The number of 16-bit groups in [s, e), a list of h16 separated by single
-- colons, the last of which may be an IPv4 address (two groups) when
-- `v4ok`; -1 if it is not one.  An empty range has no groups.
groups : ByteString -> Int -> Int -> Bool -> Int
groups bs s e v4ok = if s >= e then 0 else go s 0
  where
    go : Int -> Int -> Int
    go i k =
      let j = findFrom (== 58) bs i e in
      if j >= e
         then if h16 bs i e then k + 1
              else if v4ok && ipv4In bs i e then k + 2
              else -1
         else if h16 bs i j && j + 1 < e then go (assert_smaller i (j + 1)) (k + 1) else -1

-- The index of the first `::` in [s, e), or -1.
doubleColon : ByteString -> Int -> Int -> Int
doubleColon bs s e =
  if s + 1 >= e then -1
  else if unsafeIndex bs s == 58 && unsafeIndex bs (s + 1) == 58 then s
  else doubleColon bs (assert_smaller s (s + 1)) e

||| Is it an IPv6 address in the text form of RFC 3986 (`IPv6address`):
||| eight groups of 1 to 4 hexadecimal digits separated by colons, or fewer
||| with one `::`, and the last two groups possibly as an IPv4 address?
||| (Zone identifiers, RFC 6874, are not accepted.)
export
isIPv6 : ByteString -> Bool
isIPv6 bs =
  let e = lengthInt bs
      dc = doubleColon bs 0 e
  in if dc < 0 then groups bs 0 e True == 8
     else let l = groups bs 0 dc False
              r = groups bs (dc + 2) e True
          in l >= 0 && r >= 0 && l + r <= 7
             && doubleColon bs (dc + 1) e < 0
             -- (`:::` would make the right side start with a colon)
             && (dc + 2 >= e || unsafeIndex bs (dc + 2) /= 58)

-- `IPvFuture`: "v" 1*HEXDIG "." 1*( unreserved / sub-delims / ":" )
isIPFuture : ByteString -> Bool
isIPFuture bs =
  let e = lengthInt bs in
  if e < 4 || (unsafeIndex bs 0 /= 118 && unsafeIndex bs 0 /= 86) then False
  else let d = findFrom (== 46) bs 1 e in
       d > 1 && d + 1 < e && h16' 1 d && validIn userinfoLo userinfoHi bs (d + 1) e
         && findFrom (== 37) bs (d + 1) e == e
  where
    h16' : Int -> Int -> Bool
    h16' i d = if i >= d then True else if hexValue (unsafeIndex bs i) >= 0 then h16' (assert_smaller i (i + 1)) d else False

-- The host of [s, e).
parseHost : ByteString -> Int -> Int -> Either URIError Host
parseHost bs s e =
  if s < e && unsafeIndex bs s == 91
     then if e - s >= 2 && unsafeIndex bs (e - 1) == 93
             then let lit = sliceFromTo (s + 1) (e - 1) bs in
                  if isIPv6 lit then Right (IPv6 lit)
                  else if isIPFuture lit then Right (IPFuture lit)
                  else Left BadHost
             else Left BadHost
  else if ipv4In bs s e then Right (IPv4 (sliceFromTo s e bs))
  else if validIn regNameLo regNameHi bs s e then Right (RegName (sliceFromTo s e bs))
  else Left BadHost

-- A port of [s, e): Nothing if empty.
parsePort : ByteString -> Int -> Int -> Either URIError (Maybe Int)
parsePort bs s e =
  if s >= e then Right Nothing
  else let n = parseDecimal (sliceFromTo s e bs) in
       if n < 0 || n > 65535 then Left BadPort else Right (Just n)

-- The authority of [s, e).
parseAuthorityIn : ByteString -> Int -> Int -> Either URIError Authority
parseAuthorityIn bs s e =
  let at = lastIndexOf 64 bs s e
      hs = if at < 0 then s else at + 1
  in if at >= 0 && not (validIn userinfoLo userinfoHi bs s at) then Left BadUserinfo else
     -- The port: after the last colon that is not inside brackets.
     let close = lastIndexOf 93 bs hs e
         colon = lastIndexOf 58 bs (if close < 0 then hs else close + 1) e
         he = if colon < 0 then e else colon
     in do h <- parseHost bs hs he
           p <- if colon < 0 then Right Nothing else parsePort bs (colon + 1) e
           pure (MkAuthority (if at < 0 then Nothing else Just (sliceFromTo s at bs)) h p)

||| Parse an authority: `[userinfo "@"] host [":" port]`.
export
parseAuthority : ByteString -> Either URIError Authority
parseAuthority bs = parseAuthorityIn bs 0 (lengthInt bs)

||| Parse the value of a `Host` field (RFC 9110 section 7.2):
||| `uri-host [":" port]`, without userinfo.
export
parseHostField : ByteString -> Either URIError (Host, Maybe Int)
parseHostField bs = do
  a <- parseAuthority bs
  case a.userinfo of
    Just _ => Left BadHost
    Nothing => Right (a.host, a.port)

--------------------------------------------------------------------------
-- URIs
--------------------------------------------------------------------------

isSchemeChar : Bits8 -> Bool
isSchemeChar = inSet schemeLo schemeHi

-- The end of a scheme at the start of [0, e), the index of its colon, or -1.
schemeEnd : ByteString -> Int -> Int
schemeEnd bs e =
  if e == 0 || not (isAlpha (unsafeIndex bs 0)) then -1 else go 1
  where
    go : Int -> Int
    go i = if i >= e then -1
           else let w = unsafeIndex bs i in
                if w == 58 then i
                else if isSchemeChar w then go (assert_smaller i (i + 1)) else -1

-- The components after the scheme, from s: hier-part or relative-part,
-- query and fragment.
parseRest : Maybe ByteString -> ByteString -> Int -> Either URIError URI
parseRest sch bs s =
  let e = lengthInt bs
      hashI = findFrom (== 35) bs s e
      qI = findFrom (== 63) bs s hashI
      hasAuth = s + 1 < qI && unsafeIndex bs s == 47 && unsafeIndex bs (s + 1) == 47
      authEnd = if hasAuth then findFrom (== 47) bs (s + 2) qI else s
  in do auth <- if hasAuth then map Just (parseAuthorityIn bs (s + 2) authEnd) else Right Nothing
        let ps = authEnd
        if not (validIn pathLo pathHi bs ps qI) then Left BadPath else Right ()
        -- Without an authority a path cannot start with `//`; with one it is
        -- empty or starts with `/` (it does, by where the authority ends).
        if not hasAuth && qI - ps >= 2 && unsafeIndex bs ps == 47 && unsafeIndex bs (ps + 1) == 47
           then Left BadPath else Right ()
        -- A relative reference whose first segment has a colon would be
        -- read as a scheme.
        if isNothing sch && not hasAuth && firstSegmentHasColon ps qI then Left BadPath else Right ()
        q <- if qI < hashI
                then if validIn queryLo queryHi bs (qI + 1) hashI
                        then Right (Just (sliceFromTo (qI + 1) hashI bs)) else Left BadQuery
                else Right Nothing
        f <- if hashI < e
                then if validIn queryLo queryHi bs (hashI + 1) e
                        then Right (Just (sliceFromTo (hashI + 1) e bs)) else Left BadFragment
                else Right Nothing
        pure (MkURI sch auth (sliceFromTo ps qI bs) q f)
  where
    firstSegmentHasColon : Int -> Int -> Bool
    firstSegmentHasColon ps qe =
      let segEnd = findFrom (== 47) bs ps qe in
      findFrom (== 58) bs ps segEnd < segEnd

||| Parse a URI: `scheme ":" hier-part ["?" query] ["#" fragment]`
||| (RFC 3986 section 3).
export
parseURI : ByteString -> Either URIError URI
parseURI bs =
  let c = schemeEnd bs (lengthInt bs) in
  if c < 0 then Left BadScheme
  else parseRest (Just (takeInt c bs)) bs (c + 1)

||| Parse a URI or a relative reference (RFC 3986 section 4.1).
export
parseURIReference : ByteString -> Either URIError URI
parseURIReference bs =
  let e = lengthInt bs
      c = schemeEnd bs e
      -- A colon after a `/`, `?` or `#` is not the end of a scheme.
      firstDelim = findFrom (\w => w == 47 || w == 63 || w == 35) bs 0 e
  in if c >= 0 && c < firstDelim then parseRest (Just (takeInt c bs)) bs (c + 1)
     else parseRest Nothing bs 0

doubleSlash : ByteString
doubleSlash = "//"

-- The host as written in an authority.
hostBuilder : Host -> Builder
hostBuilder (RegName h) = byteString h
hostBuilder (IPv4 h) = byteString h
hostBuilder (IPv6 h) = word8 91 <+> byteString h <+> word8 93
hostBuilder (IPFuture h) = word8 91 <+> byteString h <+> word8 93

||| An authority as written in a URI.
export
authorityBuilder : Authority -> Builder
authorityBuilder a =
  maybe neutral (\u => byteString u <+> word8 64) a.userinfo
  <+> hostBuilder a.host
  <+> maybe neutral (\p => word8 58 <+> byteString (decimalBytes p)) a.port

||| A URI as text (RFC 3986 section 5.3).  `parseURIReference` of the
||| result gives the URI back.
export
uriBuilder : URI -> Builder
uriBuilder u =
  maybe neutral (\s => byteString s <+> word8 58) u.scheme
  <+> maybe neutral (\a => byteString doubleSlash <+> authorityBuilder a) u.authority
  <+> byteString u.path
  <+> maybe neutral (\q => word8 63 <+> byteString q) u.query
  <+> maybe neutral (\f => word8 35 <+> byteString f) u.fragment

||| `uriBuilder`, built.
export
renderURI : URI -> ByteString
renderURI = toByteString . uriBuilder

||| The text of the URI.
export
Show URI where
  show u = show (renderURI u)

--------------------------------------------------------------------------
-- Request targets (RFC 9112 section 3.2)
--------------------------------------------------------------------------

||| The target of a request.
public export
data RequestTarget
  = ||| `absolute-path ["?" query]`: the usual form.  The path starts with
    ||| `/`; both are as written (percent-encoded).
    OriginForm ByteString (Maybe ByteString)
  | ||| An absolute URI (to a proxy), without fragment.
    AbsoluteForm URI
  | ||| `host ":" port`, of `CONNECT`.
    AuthorityForm Host Int
  | ||| `*`, of a server-wide `OPTIONS`.
    AsteriskForm

||| The same target.
export
Eq RequestTarget where
  OriginForm p q == OriginForm p' q' = p == p' && q == q'
  AbsoluteForm u == AbsoluteForm u' = u == u'
  AuthorityForm h p == AuthorityForm h' p' = h == h' && p == p'
  AsteriskForm == AsteriskForm = True
  _ == _ = False

||| As the constructor and its components.
export
Show RequestTarget where
  show (OriginForm p q) = "OriginForm " ++ show p ++ " " ++ show q
  show (AbsoluteForm u) = "AbsoluteForm " ++ show u
  show (AuthorityForm h p) = "AuthorityForm (" ++ show h ++ ") " ++ show p
  show AsteriskForm = "AsteriskForm"

-- The origin form: a path that starts with `/`, then an optional query.
originForm : ByteString -> Either URIError RequestTarget
originForm bs =
  let e = lengthInt bs
      q0 = findByteFrom 63 0 bs
      q = if q0 < 0 then e else q0
  in if e == 0 || unsafeIndex bs 0 /= 47 then Left BadTargetForm
     else if not (validIn pathLo pathHi bs 0 q) then Left BadPath
     else if q < e
             then if validIn queryLo queryHi bs (q + 1) e
                     then Right (OriginForm (takeInt q bs) (Just (dropInt (q + 1) bs)))
                     else Left BadQuery
             else Right (OriginForm bs Nothing)

||| Where the query of a request target in the origin form starts: the
||| index of its `?`, -1 for a valid origin form without a query, or -2 if
||| the target is not a valid origin form (`parseRequestTarget` says why,
||| or what else it is).  For a method other than `CONNECT`, a target that
||| starts with `/` is in the origin form (see `parseRequestTarget`); this
||| checks it the same way, without allocating.
export
originFormQuery : ByteString -> Int
originFormQuery bs =
  let e = lengthInt bs
      q0 = findByteFrom 63 0 bs
      q = if q0 < 0 then e else q0
  in if e == 0 || unsafeIndex bs 0 /= 47 then -2
     else if not (validIn pathLo pathHi bs 0 q) then -2
     else if q < e then (if validIn queryLo queryHi bs (q + 1) e then q else -2)
     else -1

||| Parse a request target in the form that the method allows: the
||| authority form (with a port, no userinfo) for `CONNECT` and only for it;
||| `*` for `OPTIONS` only; otherwise the origin form, or the absolute form
||| (a URI with no fragment).
export
parseRequestTarget : Method -> ByteString -> Either URIError RequestTarget
parseRequestTarget CONNECT bs = do
  a <- parseAuthority bs
  case (a.userinfo, a.port) of
    (Nothing, Just p) => Right (AuthorityForm a.host p)
    _ => Left BadTargetForm
parseRequestTarget m bs =
  if lengthInt bs == 1 && unsafeIndex bs 0 == 42
     then if m == OPTIONS then Right AsteriskForm else Left BadTargetForm
  else if lengthInt bs > 0 && unsafeIndex bs 0 == 47 then originForm bs
  else do u <- parseURI bs
          case u.fragment of
            Nothing => Right (AbsoluteForm u)
            Just _ => Left BadTargetForm

--------------------------------------------------------------------------
-- Percent-encoding (RFC 3986 section 2.1)
--------------------------------------------------------------------------

-- The number of bytes of the decoding of bs, or -1 if a `%` is not
-- followed by two hexadecimal digits.  `plus`: `+` is a space (it is
-- one byte either way).
decodedSize : Bool -> ByteString -> Int
decodedSize strict bs = go 0 0
  where
    go : Int -> Int -> Int
    go i n =
      if i >= lengthInt bs then n
      else if unsafeIndex bs i == 37
              then if i + 2 < lengthInt bs && hexValue (unsafeIndex bs (i + 1)) >= 0 && hexValue (unsafeIndex bs (i + 2)) >= 0
                      then go (assert_smaller i (i + 3)) (n + 1)
                      else if strict then -1 else go (assert_smaller i (i + 1)) (n + 1)
              else go (assert_smaller i (i + 1)) (n + 1)

-- Write the decoding of bs at 0.
decodeInto : Bool -> ByteString -> Buffer -> Int -> Int -> IO ()
decodeInto plus bs buf i o =
  if i >= lengthInt bs then pure ()
  else let w = unsafeIndex bs i in
       if w == 37 && i + 2 < lengthInt bs && hexValue (unsafeIndex bs (i + 1)) >= 0 && hexValue (unsafeIndex bs (i + 2)) >= 0
          then do setBits8 buf o (cast (hexValue (unsafeIndex bs (i + 1)) * 16 + hexValue (unsafeIndex bs (i + 2))))
                  decodeInto plus bs buf (assert_smaller i (i + 3)) (o + 1)
          else do setBits8 buf o (if plus && w == 43 then 32 else w)
                  decodeInto plus bs buf (assert_smaller i (i + 1)) (o + 1)

-- Decode, as described for `percentDecode` (strict) or `formDecode`.
decodeWith : (strict, plus : Bool) -> ByteString -> Maybe ByteString
decodeWith strict plus bs =
  let n = decodedSize strict bs in
  if n < 0 then Nothing
  else if n == lengthInt bs && not (plus && isJust (find' 43))
          then Just bs
          else Just (unsafeCreate n (\buf => decodeInto plus bs buf 0 0))
  where
    find' : Bits8 -> Maybe Int
    find' w = let i = findByteFrom w 0 bs in if i < 0 then Nothing else Just i

||| Decode `%XX` sequences.  `Nothing` if a `%` is not followed by two
||| hexadecimal digits.  Other bytes are kept as they are (the result may
||| not be UTF-8; see `Data.ByteString.toString`).  Returns its argument,
||| not a copy, when there is nothing to decode.
export
percentDecode : ByteString -> Maybe ByteString
percentDecode = decodeWith True False

hexUpper : Int -> Bits8
hexUpper d = if d < 10 then cast (48 + d) else cast (55 + d)

-- The size of the encoding.
encodedSize : (Bits8 -> Bool) -> Bool -> ByteString -> Int
encodedSize keep plus bs = go 0 0
  where
    go : Int -> Int -> Int
    go i n = if i >= lengthInt bs then n
             else let w = unsafeIndex bs i in
                  go (assert_smaller i (i + 1)) (if keep w || (plus && w == 32) then n + 1 else n + 3)

encodeInto : (Bits8 -> Bool) -> Bool -> ByteString -> Buffer -> Int -> Int -> IO ()
encodeInto keep plus bs buf i o =
  if i >= lengthInt bs then pure ()
  else let w = unsafeIndex bs i in
       if keep w then do setBits8 buf o w
                         encodeInto keep plus bs buf (assert_smaller i (i + 1)) (o + 1)
       else if plus && w == 32 then do setBits8 buf o 43
                                       encodeInto keep plus bs buf (assert_smaller i (i + 1)) (o + 1)
       else do setBits8 buf o 37
               setBits8 buf (o + 1) (hexUpper (cast (w `shiftR` 4)))
               setBits8 buf (o + 2) (hexUpper (cast (w .&. 15)))
               encodeInto keep plus bs buf (assert_smaller i (i + 1)) (o + 3)

-- Encode the bytes that are not kept.
encodeWith : (Bits8 -> Bool) -> (plus : Bool) -> ByteString -> ByteString
encodeWith keep plus bs =
  let n = encodedSize keep plus bs in
  if n == lengthInt bs && not plus then bs
  else unsafeCreate n (\buf => encodeInto keep plus bs buf 0 0)

||| Percent-encode (with upper-case digits, as RFC 3986 section 2.1
||| recommends) every byte for which the predicate does not hold.  `%` is
||| encoded whatever the predicate says, so that decoding gives the input
||| back.
export
percentEncode : (keep : Bits8 -> Bool) -> ByteString -> ByteString
percentEncode keep = encodeWith (\w => w /= 37 && keep w) False

||| Encode for a path segment: everything but `unreserved`, `sub-delims`,
||| `:` and `@` (so `/` and `?` are encoded).
export
encodePathSegment : ByteString -> ByteString
encodePathSegment = percentEncode isPChar

||| Encode for a path: as a segment, but `/` is kept.
export
encodePath : ByteString -> ByteString
encodePath = percentEncode (inSet pathLo pathHi)

||| Encode for a query or a fragment: as a path, but `?` is kept too.
||| (This keeps `&`, `=` and `+`, the delimiters of form data: use
||| `formEncode` for keys and values.)
export
encodeQuery : ByteString -> ByteString
encodeQuery = percentEncode (inSet queryLo queryHi)

||| Encode for the userinfo: everything but `unreserved`, `sub-delims` and
||| `:`.
export
encodeUserinfo : ByteString -> ByteString
encodeUserinfo = percentEncode (inSet userinfoLo userinfoHi)

--------------------------------------------------------------------------
-- Form data (application/x-www-form-urlencoded)
--------------------------------------------------------------------------

||| Decode a key or value of form data: `+` is a space and `%XX` a byte; a
||| `%` that is not followed by two hexadecimal digits is kept as it is (as
||| the WHATWG URL standard does), so this never fails.
export
formDecode : ByteString -> ByteString
formDecode bs = fromMaybe bs (decodeWith False True bs)

||| Encode a key or value of form data: a space is `+`; letters, digits and
||| `*-._` are kept; every other byte is `%XX`.
export
formEncodeComponent : ByteString -> ByteString
formEncodeComponent = encodeWith (inSet formLo formHi) True

ampersand : ByteString
ampersand = "&"

||| The pairs as form data: `k1=v1&k2=v2`, each key and value encoded with
||| `formEncodeComponent`.
export
formEncode : List (ByteString, ByteString) -> ByteString
formEncode kvs =
  toByteString (go True kvs neutral)
  where
    go : Bool -> List (ByteString, ByteString) -> Builder -> Builder
    go _ [] acc = acc
    go first ((k, v) :: rest) acc =
      go False rest (acc <+> (if first then neutral else word8 38)
                         <+> byteString (formEncodeComponent k) <+> word8 61
                         <+> byteString (formEncodeComponent v))

||| The pairs of a query string or of form data: split at `&`, each part at
||| its first `=` (a part without `=` is a key with an empty value), and each
||| key and value decoded with `formDecode`.  Empty parts are skipped (as in
||| the WHATWG URL standard); keys may repeat, and the order is kept.
export
parseQuery : ByteString -> List (ByteString, ByteString)
parseQuery bs = go 0 []
  where
    pair : Int -> Int -> (ByteString, ByteString)
    pair s e = let eq = findFrom (== 61) bs s e in
               if eq < e then (formDecode (sliceFromTo s eq bs), formDecode (sliceFromTo (eq + 1) e bs))
               else (formDecode (sliceFromTo s e bs), Data.ByteString.empty)
    go : Int -> List (ByteString, ByteString) -> List (ByteString, ByteString)
    go s acc =
      if s > lengthInt bs then reverse acc
      else let e = findFrom (== 38) bs s (lengthInt bs)
               acc' = if e > s then pair s e :: acc else acc
           in go (assert_smaller s (e + 1)) acc'

--------------------------------------------------------------------------
-- Dot segments and resolution (RFC 3986 section 5.2)
--------------------------------------------------------------------------

-- Do the bytes from i equal the ASCII text of the list (all of them)?
startsAt : ByteString -> Int -> List Bits8 -> Bool
startsAt bs i [] = True
startsAt bs i (w :: ws) = i < lengthInt bs && unsafeIndex bs i == w && startsAt bs (i + 1) ws

-- Are the bytes from i exactly the list?
restIs : ByteString -> Int -> List Bits8 -> Bool
restIs bs i ws = lengthInt bs - i == cast (length ws) && startsAt bs i ws

slashBS : ByteString
slashBS = "/"

||| Remove the `.` and `..` segments of a path, with the algorithm of RFC
||| 3986 section 5.2.4: `/a/b/c/./../../g` is `/a/g`, and a `..` above the
||| root is dropped (`/../a` is `/a`).  Percent-encoded dots (`%2E`) are not
||| dot segments (decode first if they should be).
export
removeDotSegments : ByteString -> ByteString
removeDotSegments bs = Data.ByteString.concat (reverse (go 0 []))
  where
    pop : List ByteString -> List ByteString
    pop [] = []
    pop (_ :: xs) = xs
    -- `out`: the segments written so far (each with its `/`), last first.
    go : Int -> List ByteString -> List ByteString
    go i out =
      if i >= lengthInt bs then out
      -- A: "../" or "./"
      else if startsAt bs i [46, 46, 47] then go (assert_smaller i (i + 3)) out
      else if startsAt bs i [46, 47] then go (assert_smaller i (i + 2)) out
      -- B: "/./" or "/." at the end
      else if startsAt bs i [47, 46, 47] then go (assert_smaller i (i + 2)) out
      else if restIs bs i [47, 46] then slashBS :: out
      -- C: "/../" or "/.." at the end
      else if startsAt bs i [47, 46, 46, 47] then go (assert_smaller i (i + 3)) (pop out)
      else if restIs bs i [47, 46, 46] then slashBS :: pop out
      -- D: "." or ".." alone
      else if restIs bs i [46] || restIs bs i [46, 46] then out
      -- E: the first segment, with its "/" if it has one
      else let j = findByteFrom 47 (if unsafeIndex bs i == 47 then i + 1 else i) bs
               j' = if j < 0 then lengthInt bs else j
           in go (assert_smaller i j') (sliceFromTo i j' bs :: out)

-- RFC 3986 section 5.2.3.
merge : URI -> ByteString -> ByteString
merge base rel =
  if isJust base.authority && lengthInt base.path == 0
     then slashBS <+> rel
     else let k = lastIndexOf 47 base.path 0 (lengthInt base.path) in
          if k < 0 then rel else takeInt (k + 1) base.path <+> rel

||| Resolve a reference against a base URI (RFC 3986 section 5.2.2, the
||| strict algorithm: a reference with the scheme of the base is not
||| treated as relative).  The base should be a URI (with a scheme) and
||| its fragment is not used.
export
resolve : (base : URI) -> (ref : URI) -> URI
resolve base r =
  case r.scheme of
    Just _ => { path := removeDotSegments r.path } r
    Nothing =>
      case r.authority of
        Just _ => { scheme := base.scheme, path := removeDotSegments r.path } r
        Nothing =>
          let (p, q) = if lengthInt r.path == 0
                          then (base.path, if isJust r.query then r.query else base.query)
                          else if unsafeIndex r.path 0 == 47
                                  then (removeDotSegments r.path, r.query)
                                  else (removeDotSegments (merge base r.path), r.query)
          in MkURI base.scheme base.authority p q r.fragment
