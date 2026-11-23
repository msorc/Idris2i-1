||| The vocabulary of HTTP messages: methods, status codes, versions, header
||| fields and the heads of requests and responses.
|||
||| # The `http` library
|||
||| The library has the parts of an HTTP stack that are pure functions of
||| bytes, with no sockets and no input or output: a connection loop reads
||| buffers from wherever it likes and feeds them to these.
|||
|||  * `Network.HTTP.Types`: this module.
|||  * `Network.HTTP.Parser`: incremental parsers of HTTP/1.1 request and
|||    response heads (RFC 9112), and the framing of the body that follows.
|||  * `Network.HTTP.Chunked`: the chunked transfer coding, both directions.
|||  * `Network.HTTP.Render`: request and response heads as bytes.
|||  * `Network.URI`: URIs and request targets (RFC 3986), percent coding,
|||    query strings.
|||  * `Network.HTTP2.HPACK` and `Network.HTTP2.Frame`: header compression
|||    (RFC 7541) and the frames of HTTP/2 (RFC 9113).
|||  * `Network.WebSocket.Frame` and friends: WebSocket frames and the
|||    opening handshake (RFC 6455).
|||  * `Network.HTTP.SHA1` and `Network.HTTP.Base64`: what the WebSocket
|||    handshake needs.
|||
||| All of them take `Data.ByteString.ByteString` and produce slices of
||| their input where they can (a parsed header name is a slice of the buffer
||| it was read from, not a copy), and the serialisers produce
||| `Data.ByteString.Builder.Builder`.
module Network.HTTP.Types

import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal
import Data.List
import Data.Maybe
import Network.HTTP.Internal.Bytes

%default total

emptyBS : ByteString
emptyBS = Data.ByteString.empty

--------------------------------------------------------------------------
-- Methods
--------------------------------------------------------------------------

||| A request method (RFC 9110 section 9).  The methods of RFC 9110 and
||| PATCH (RFC 5789) have constructors; any other token is `OtherMethod`.
||| Methods are case sensitive: `get` is an `OtherMethod`.
public export
data Method
  = GET | HEAD | POST | PUT | DELETE | CONNECT | OPTIONS | TRACE | PATCH
  | ||| Any other method token, as it was received.
    OtherMethod ByteString

||| Equal methods: the same constructor, or the same bytes of `OtherMethod`.
export
Eq Method where
  GET == GET = True
  HEAD == HEAD = True
  POST == POST = True
  PUT == PUT = True
  DELETE == DELETE = True
  CONNECT == CONNECT = True
  OPTIONS == OPTIONS = True
  TRACE == TRACE = True
  PATCH == PATCH = True
  OtherMethod x == OtherMethod y = x == y
  _ == _ = False

mGET, mHEAD, mPOST, mPUT, mDELETE, mCONNECT, mOPTIONS, mTRACE, mPATCH : ByteString
mGET = "GET"
mHEAD = "HEAD"
mPOST = "POST"
mPUT = "PUT"
mDELETE = "DELETE"
mCONNECT = "CONNECT"
mOPTIONS = "OPTIONS"
mTRACE = "TRACE"
mPATCH = "PATCH"

||| The method token as bytes (for `OtherMethod`, the bytes it holds).
export
methodBytes : Method -> ByteString
methodBytes GET = mGET
methodBytes HEAD = mHEAD
methodBytes POST = mPOST
methodBytes PUT = mPUT
methodBytes DELETE = mDELETE
methodBytes CONNECT = mCONNECT
methodBytes OPTIONS = mOPTIONS
methodBytes TRACE = mTRACE
methodBytes PATCH = mPATCH
methodBytes (OtherMethod m) = m

||| The method of a token (case sensitive).  Does not check that the bytes
||| are a token; `Network.HTTP.Parser` does when it reads a request line.
||| Does not allocate for the methods that have a constructor.
export
methodFromBytes : ByteString -> Method
methodFromBytes bs =
  case lengthInt bs of
    3 => if sameBytes bs mGET then GET else if sameBytes bs mPUT then PUT else OtherMethod bs
    4 => if sameBytes bs mPOST then POST else if sameBytes bs mHEAD then HEAD else OtherMethod bs
    5 => if sameBytes bs mPATCH then PATCH else if sameBytes bs mTRACE then TRACE else OtherMethod bs
    6 => if sameBytes bs mDELETE then DELETE else OtherMethod bs
    7 => if sameBytes bs mOPTIONS then OPTIONS else if sameBytes bs mCONNECT then CONNECT else OtherMethod bs
    _ => OtherMethod bs

||| The method token, as text (Latin-1 for bytes that are not ASCII).
export
Show Method where
  show m = toStringLossy (methodBytes m)

||| Is a request with this method safe (RFC 9110 section 9.2.1)?
export
isSafe : Method -> Bool
isSafe GET = True
isSafe HEAD = True
isSafe OPTIONS = True
isSafe TRACE = True
isSafe _ = False

||| Is a request with this method idempotent (RFC 9110 section 9.2.2)?
export
isIdempotent : Method -> Bool
isIdempotent PUT = True
isIdempotent DELETE = True
isIdempotent m = isSafe m

--------------------------------------------------------------------------
-- Versions
--------------------------------------------------------------------------

||| An HTTP version: major and minor digit.
public export
record Version where
  constructor MkVersion
  major : Int
  minor : Int

||| Same digits.
export
Eq Version where
  MkVersion a b == MkVersion c d = a == c && b == d

||| By major, then minor digit.
export
Ord Version where
  compare (MkVersion a b) (MkVersion c d) = case compare a c of
                                                 EQ => compare b d
                                                 o => o

||| `HTTP/1.0`.
export
http10 : Version
http10 = MkVersion 1 0

||| `HTTP/1.1`.
export
http11 : Version
http11 = MkVersion 1 1

||| As in a message: `HTTP/1.1`.
export
Show Version where
  show (MkVersion a b) = "HTTP/" ++ show a ++ "." ++ show b

--------------------------------------------------------------------------
-- Status codes
--------------------------------------------------------------------------

||| A status code and its reason phrase.  The constants below have the
||| phrases of RFC 9110 section 15; `statusFromCode` finds them.
public export
record Status where
  constructor MkStatus
  ||| The three-digit code (100..999 for a valid one).
  code : Int
  ||| The reason phrase (may be empty).
  reason : ByteString

||| The same code (the reason phrases are not compared).
export
Eq Status where
  x == y = x.code == y.code

||| `200 OK`.
export
Show Status where
  show s = show s.code ++ " " ++ toStringLossy s.reason

||| 1xx: interim response.
export
isInformational : Status -> Bool
isInformational s = s.code >= 100 && s.code < 200

||| 2xx.
export
isSuccessful : Status -> Bool
isSuccessful s = s.code >= 200 && s.code < 300

||| 3xx.
export
isRedirection : Status -> Bool
isRedirection s = s.code >= 300 && s.code < 400

||| 4xx.
export
isClientError : Status -> Bool
isClientError s = s.code >= 400 && s.code < 500

||| 5xx.
export
isServerError : Status -> Bool
isServerError s = s.code >= 500 && s.code < 600

||| 100 Continue.
export
statusContinue : Status
statusContinue = MkStatus 100 "Continue"

||| 101 Switching Protocols.
export
statusSwitchingProtocols : Status
statusSwitchingProtocols = MkStatus 101 "Switching Protocols"

||| 200 OK.
export
statusOK : Status
statusOK = MkStatus 200 "OK"

||| 201 Created.
export
statusCreated : Status
statusCreated = MkStatus 201 "Created"

||| 202 Accepted.
export
statusAccepted : Status
statusAccepted = MkStatus 202 "Accepted"

||| 203 Non-Authoritative Information.
export
statusNonAuthoritativeInfo : Status
statusNonAuthoritativeInfo = MkStatus 203 "Non-Authoritative Information"

||| 204 No Content.
export
statusNoContent : Status
statusNoContent = MkStatus 204 "No Content"

||| 205 Reset Content.
export
statusResetContent : Status
statusResetContent = MkStatus 205 "Reset Content"

||| 206 Partial Content.
export
statusPartialContent : Status
statusPartialContent = MkStatus 206 "Partial Content"

||| 300 Multiple Choices.
export
statusMultipleChoices : Status
statusMultipleChoices = MkStatus 300 "Multiple Choices"

||| 301 Moved Permanently.
export
statusMovedPermanently : Status
statusMovedPermanently = MkStatus 301 "Moved Permanently"

||| 302 Found.
export
statusFound : Status
statusFound = MkStatus 302 "Found"

||| 303 See Other.
export
statusSeeOther : Status
statusSeeOther = MkStatus 303 "See Other"

||| 304 Not Modified.
export
statusNotModified : Status
statusNotModified = MkStatus 304 "Not Modified"

||| 305 Use Proxy.
export
statusUseProxy : Status
statusUseProxy = MkStatus 305 "Use Proxy"

||| 307 Temporary Redirect.
export
statusTemporaryRedirect : Status
statusTemporaryRedirect = MkStatus 307 "Temporary Redirect"

||| 308 Permanent Redirect.
export
statusPermanentRedirect : Status
statusPermanentRedirect = MkStatus 308 "Permanent Redirect"

||| 400 Bad Request.
export
statusBadRequest : Status
statusBadRequest = MkStatus 400 "Bad Request"

||| 401 Unauthorized.
export
statusUnauthorized : Status
statusUnauthorized = MkStatus 401 "Unauthorized"

||| 402 Payment Required.
export
statusPaymentRequired : Status
statusPaymentRequired = MkStatus 402 "Payment Required"

||| 403 Forbidden.
export
statusForbidden : Status
statusForbidden = MkStatus 403 "Forbidden"

||| 404 Not Found.
export
statusNotFound : Status
statusNotFound = MkStatus 404 "Not Found"

||| 405 Method Not Allowed.
export
statusMethodNotAllowed : Status
statusMethodNotAllowed = MkStatus 405 "Method Not Allowed"

||| 406 Not Acceptable.
export
statusNotAcceptable : Status
statusNotAcceptable = MkStatus 406 "Not Acceptable"

||| 407 Proxy Authentication Required.
export
statusProxyAuthRequired : Status
statusProxyAuthRequired = MkStatus 407 "Proxy Authentication Required"

||| 408 Request Timeout.
export
statusRequestTimeout : Status
statusRequestTimeout = MkStatus 408 "Request Timeout"

||| 409 Conflict.
export
statusConflict : Status
statusConflict = MkStatus 409 "Conflict"

||| 410 Gone.
export
statusGone : Status
statusGone = MkStatus 410 "Gone"

||| 411 Length Required.
export
statusLengthRequired : Status
statusLengthRequired = MkStatus 411 "Length Required"

||| 412 Precondition Failed.
export
statusPreconditionFailed : Status
statusPreconditionFailed = MkStatus 412 "Precondition Failed"

||| 413 Content Too Large.
export
statusContentTooLarge : Status
statusContentTooLarge = MkStatus 413 "Content Too Large"

||| 414 URI Too Long.
export
statusURITooLong : Status
statusURITooLong = MkStatus 414 "URI Too Long"

||| 415 Unsupported Media Type.
export
statusUnsupportedMediaType : Status
statusUnsupportedMediaType = MkStatus 415 "Unsupported Media Type"

||| 416 Range Not Satisfiable.
export
statusRangeNotSatisfiable : Status
statusRangeNotSatisfiable = MkStatus 416 "Range Not Satisfiable"

||| 417 Expectation Failed.
export
statusExpectationFailed : Status
statusExpectationFailed = MkStatus 417 "Expectation Failed"

||| 421 Misdirected Request.
export
statusMisdirectedRequest : Status
statusMisdirectedRequest = MkStatus 421 "Misdirected Request"

||| 422 Unprocessable Content.
export
statusUnprocessableContent : Status
statusUnprocessableContent = MkStatus 422 "Unprocessable Content"

||| 426 Upgrade Required.
export
statusUpgradeRequired : Status
statusUpgradeRequired = MkStatus 426 "Upgrade Required"

||| 428 Precondition Required.
export
statusPreconditionRequired : Status
statusPreconditionRequired = MkStatus 428 "Precondition Required"

||| 429 Too Many Requests.
export
statusTooManyRequests : Status
statusTooManyRequests = MkStatus 429 "Too Many Requests"

||| 431 Request Header Fields Too Large.
export
statusRequestHeaderFieldsTooLarge : Status
statusRequestHeaderFieldsTooLarge = MkStatus 431 "Request Header Fields Too Large"

||| 500 Internal Server Error.
export
statusInternalServerError : Status
statusInternalServerError = MkStatus 500 "Internal Server Error"

||| 501 Not Implemented.
export
statusNotImplemented : Status
statusNotImplemented = MkStatus 501 "Not Implemented"

||| 502 Bad Gateway.
export
statusBadGateway : Status
statusBadGateway = MkStatus 502 "Bad Gateway"

||| 503 Service Unavailable.
export
statusServiceUnavailable : Status
statusServiceUnavailable = MkStatus 503 "Service Unavailable"

||| 504 Gateway Timeout.
export
statusGatewayTimeout : Status
statusGatewayTimeout = MkStatus 504 "Gateway Timeout"

||| 505 HTTP Version Not Supported.
export
statusHTTPVersionNotSupported : Status
statusHTTPVersionNotSupported = MkStatus 505 "HTTP Version Not Supported"

||| The status with a code, with the reason phrase of RFC 9110 if the code
||| is registered there (or is 429, 428 or 431 of RFC 6585), and an empty one
||| otherwise.  Constant time; does not allocate for registered codes.
export
statusFromCode : Int -> Status
statusFromCode n = case n of
  100 => statusContinue
  101 => statusSwitchingProtocols
  200 => statusOK
  201 => statusCreated
  202 => statusAccepted
  203 => statusNonAuthoritativeInfo
  204 => statusNoContent
  205 => statusResetContent
  206 => statusPartialContent
  300 => statusMultipleChoices
  301 => statusMovedPermanently
  302 => statusFound
  303 => statusSeeOther
  304 => statusNotModified
  305 => statusUseProxy
  307 => statusTemporaryRedirect
  308 => statusPermanentRedirect
  400 => statusBadRequest
  401 => statusUnauthorized
  402 => statusPaymentRequired
  403 => statusForbidden
  404 => statusNotFound
  405 => statusMethodNotAllowed
  406 => statusNotAcceptable
  407 => statusProxyAuthRequired
  408 => statusRequestTimeout
  409 => statusConflict
  410 => statusGone
  411 => statusLengthRequired
  412 => statusPreconditionFailed
  413 => statusContentTooLarge
  414 => statusURITooLong
  415 => statusUnsupportedMediaType
  416 => statusRangeNotSatisfiable
  417 => statusExpectationFailed
  421 => statusMisdirectedRequest
  422 => statusUnprocessableContent
  426 => statusUpgradeRequired
  428 => statusPreconditionRequired
  429 => statusTooManyRequests
  431 => statusRequestHeaderFieldsTooLarge
  500 => statusInternalServerError
  501 => statusNotImplemented
  502 => statusBadGateway
  503 => statusServiceUnavailable
  504 => statusGatewayTimeout
  505 => statusHTTPVersionNotSupported
  _ => MkStatus n emptyBS

--------------------------------------------------------------------------
-- Header fields
--------------------------------------------------------------------------

||| A header (or trailer) field.  The name has the case in which it was
||| received or given; the value has no leading or trailing spaces or tabs.
public export
record Header where
  constructor MkHeader
  name : ByteString
  value : ByteString

||| `name: value`.
export
Show Header where
  show h = toStringLossy h.name ++ ": " ++ toStringLossy h.value

||| The same name (ignoring ASCII case) and the same value.
export
Eq Header where
  x == y = eqIgnoreCase x.name y.name && x.value == y.value

||| The header fields of a message, in the order in which they were received
||| or added, with duplicates.  Names are compared without regard to ASCII
||| case, without allocating: a lookup walks the fields and compares the
||| lengths first, which is what it costs for the dozen or so fields of a
||| typical message.
|||
||| The fields are kept the last first, the order in which a parser finds
||| them, so that making the collection does not reverse a list and adding a
||| field takes constant time.
export
data Headers : Type where
  MkHeaders : (lastFirst : List Header) -> Headers

||| No fields.
export
emptyHeaders : Headers
emptyHeaders = MkHeaders []

||| The fields of a list, in its order.
export
headersFromList : List Header -> Headers
headersFromList hs = MkHeaders (reverse hs)

||| The fields of a list that has the last field first (as a parser
||| collects them).  Constant time.
export
headersFromListRev : List Header -> Headers
headersFromListRev = MkHeaders

||| The fields given as pairs of name and value, in the order of the list.
export
headersFromPairs : List (ByteString, ByteString) -> Headers
headersFromPairs ps = headersFromList (map (\(n, v) => MkHeader n v) ps)

||| The fields, in order.  Linear.
export
headersToList : Headers -> List Header
headersToList (MkHeaders hs) = reverse hs

||| The fields, the last first.  Constant time.
export
headersToListRev : Headers -> List Header
headersToListRev (MkHeaders hs) = hs

||| The number of fields (each duplicate counts).
export
headerCount : Headers -> Nat
headerCount (MkHeaders hs) = length hs

||| In order and with the names compared ignoring case.
export
Eq Headers where
  MkHeaders xs == MkHeaders ys = xs == ys

||| As the list of the fields in order.
export
Show Headers where
  show hs = show (headersToList hs)

-- The value of the first field (in order) with a name: the last one found
-- in the list, which has the last field first.
lastNamed : ByteString -> List Header -> Maybe ByteString -> Maybe ByteString
lastNamed n [] found = found
lastNamed n (h :: hs) found = lastNamed n hs (if eqIgnoreCase h.name n then Just h.value else found)

||| The value of the first field with a name (compared ignoring case).
export
lookupHeader : (name : ByteString) -> Headers -> Maybe ByteString
lookupHeader n (MkHeaders hs) = lastNamed n hs Nothing

||| The values of all the fields with a name, in order.
export
lookupHeaders : (name : ByteString) -> Headers -> List ByteString
lookupHeaders n (MkHeaders hs) = go hs []
  where
    go : List Header -> List ByteString -> List ByteString
    go [] acc = acc
    go (h :: rest) acc = go rest (if eqIgnoreCase h.name n then h.value :: acc else acc)

||| Is there a field with this name?
export
hasHeader : (name : ByteString) -> Headers -> Bool
hasHeader n (MkHeaders hs) = go hs
  where
    go : List Header -> Bool
    go [] = False
    go (h :: rest) = if eqIgnoreCase h.name n then True else go rest

||| A field added after the others.  Constant time.
export
addHeader : (name, value : ByteString) -> Headers -> Headers
addHeader n v (MkHeaders hs) = MkHeaders (MkHeader n v :: hs)

||| Without the fields with this name.
export
removeHeader : (name : ByteString) -> Headers -> Headers
removeHeader n (MkHeaders hs) = MkHeaders (filter (\h => not (eqIgnoreCase h.name n)) hs)

||| One field with this name and value in place of all those with the name:
||| at the position of the first of them, or after the others if there was
||| none.
export
setHeader : (name, value : ByteString) -> Headers -> Headers
setHeader n v hs = headersFromList (go False (headersToList hs))
  where
    go : Bool -> List Header -> List Header
    go False [] = [MkHeader n v]
    go True [] = []
    go done (h :: rest) =
      if eqIgnoreCase h.name n
         then if done then go True rest else MkHeader n v :: go True rest
         else h :: go done rest

comma : ByteString
comma = ", "

||| The values of the fields with a name joined with `", "`, as RFC 9110
||| section 5.3 allows for fields whose value is a list (not for
||| `Set-Cookie`).  `Nothing` if there is no such field.
export
combinedHeader : (name : ByteString) -> Headers -> Maybe ByteString
combinedHeader n hs = case lookupHeaders n hs of
                           [] => Nothing
                           [v] => Just v
                           vs => Just (intercalate comma vs)

||| Does a field whose value is a comma-separated list of tokens (such as
||| `Connection` or `Transfer-Encoding`) have the token in one of its
||| occurrences?  Tokens are compared ignoring case.
export
headerHasToken : (name, token : ByteString) -> Headers -> Bool
headerHasToken n tok (MkHeaders hs) = go hs
  where
    go : List Header -> Bool
    go [] = False
    go (h :: rest) = (eqIgnoreCase h.name n && listHasToken tok h.value) || go rest

-- Are all the bytes of the buffer in [i, e) token characters (or, for
-- values, field-value characters)?  Loops over the bytes, four at a time
-- for values, without the closure of `Data.ByteString.all`: the server
-- checks every field of every response.
allTChar : Buffer -> Int -> Int -> Bool
allTChar b i e = if i >= e then True
                 else if isTChar (unsafeBufferByte b i) then allTChar b (assert_smaller i (i + 1)) e
                 else False

allFieldVChar1 : Buffer -> Int -> Int -> Bool
allFieldVChar1 b i e = if i >= e then True
                       else if isFieldVChar (unsafeBufferByte b i) then allFieldVChar1 b (assert_smaller i (i + 1)) e
                       else False

allFieldVChar : Buffer -> Int -> Int -> Bool
allFieldVChar b i e =
  if i + 4 <= e
     then let w = unsafeBufferWord32LE b i in
          -- (a tab is below 0x20: its word is looked at byte by byte)
          if hasByteBelow w 0x20 || hasByteEq w 0x7F
             then allFieldVChar1 b i (i + 4) && allFieldVChar b (assert_smaller i (i + 4)) e
             else allFieldVChar b (assert_smaller i (i + 4)) e
     else allFieldVChar1 b i e

||| Is the byte string a valid field name (a non-empty token)?
export
isValidHeaderName : ByteString -> Bool
isValidHeaderName (UnsafeBS b o n) = n > 0 && allTChar b o (o + n)

||| Is the byte string a valid field value: no CR, LF, NUL or other control
||| character than horizontal tab, and no leading or trailing whitespace?
||| A serialiser that writes a value that is not valid lets a sender inject
||| fields (response splitting); `Network.HTTP.Render` does not check, so a
||| program that puts untrusted text in a field should check it with this.
export
isValidHeaderValue : ByteString -> Bool
isValidHeaderValue (UnsafeBS b o n) =
  allFieldVChar b o (o + n) &&
  (n == 0 || (not (isOWS (unsafeBufferByte b o)) && not (isOWS (unsafeBufferByte b (o + n - 1)))))

||| The first field whose name or value is not valid, if there is one.
export
invalidHeader : Headers -> Maybe Header
invalidHeader (MkHeaders hs) = go hs Nothing
  where
    -- (the list has the last field first: the last one found is the first)
    go : List Header -> Maybe Header -> Maybe Header
    go [] found = found
    go (h :: rest) found =
      go rest (if isValidHeaderName h.name && isValidHeaderValue h.value then found else Just h)

--------------------------------------------------------------------------
-- Field names that the library uses (in lower case)
--------------------------------------------------------------------------

||| `host`
export
hHost : ByteString
hHost = "host"

||| `content-length`
export
hContentLength : ByteString
hContentLength = "content-length"

||| `transfer-encoding`
export
hTransferEncoding : ByteString
hTransferEncoding = "transfer-encoding"

||| `connection`
export
hConnection : ByteString
hConnection = "connection"

||| `content-type`
export
hContentType : ByteString
hContentType = "content-type"

||| `upgrade`
export
hUpgrade : ByteString
hUpgrade = "upgrade"

||| `te`
export
hTE : ByteString
hTE = "te"

||| `trailer`
export
hTrailer : ByteString
hTrailer = "trailer"

||| `expect`
export
hExpect : ByteString
hExpect = "expect"

||| `keep-alive`
export
hKeepAlive : ByteString
hKeepAlive = "keep-alive"

||| `date`
export
hDate : ByteString
hDate = "date"

||| `server`
export
hServer : ByteString
hServer = "server"

||| `user-agent`
export
hUserAgent : ByteString
hUserAgent = "user-agent"

||| `accept`
export
hAccept : ByteString
hAccept = "accept"

||| `cookie`
export
hCookie : ByteString
hCookie = "cookie"

||| `set-cookie`
export
hSetCookie : ByteString
hSetCookie = "set-cookie"

||| `authorization`
export
hAuthorization : ByteString
hAuthorization = "authorization"

||| `location`
export
hLocation : ByteString
hLocation = "location"

||| `sec-websocket-key`
export
hSecWebSocketKey : ByteString
hSecWebSocketKey = "sec-websocket-key"

||| `sec-websocket-accept`
export
hSecWebSocketAccept : ByteString
hSecWebSocketAccept = "sec-websocket-accept"

||| `sec-websocket-version`
export
hSecWebSocketVersion : ByteString
hSecWebSocketVersion = "sec-websocket-version"

||| `sec-websocket-protocol`
export
hSecWebSocketProtocol : ByteString
hSecWebSocketProtocol = "sec-websocket-protocol"

||| `sec-websocket-extensions`
export
hSecWebSocketExtensions : ByteString
hSecWebSocketExtensions = "sec-websocket-extensions"

||| `http2-settings`
export
hHTTP2Settings : ByteString
hHTTP2Settings = "http2-settings"

--------------------------------------------------------------------------
-- Message heads
--------------------------------------------------------------------------

||| The head of a request: the request line and the header fields.
public export
record RequestHead where
  constructor MkRequestHead
  method : Method
  ||| The request target as it was received (see `Network.URI` to parse it).
  target : ByteString
  version : Version
  headers : Headers

||| The head of a response: the status line and the header fields.
public export
record ResponseHead where
  constructor MkResponseHead
  version : Version
  ||| The code, and the reason phrase as it was received or is to be sent.
  status : Status
  headers : Headers

||| The request line and the fields, for tests and logs.
export
Show RequestHead where
  show r = show r.method ++ " " ++ toStringLossy r.target ++ " " ++ show r.version
           ++ " " ++ show r.headers

||| The status line and the fields, for tests and logs.
export
Show ResponseHead where
  show r = show r.version ++ " " ++ show r.status ++ " " ++ show r.headers

||| The same request line and fields.
export
Eq RequestHead where
  x == y = x.method == y.method && x.target == y.target && x.version == y.version
           && x.headers == y.headers

||| The same version, code, reason phrase and fields.
export
Eq ResponseHead where
  x == y = x.version == y.version && x.status.code == y.status.code
           && x.status.reason == y.status.reason && x.headers == y.headers
