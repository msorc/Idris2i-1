||| Routing requests by method and path, and JSON bodies.
|||
||| ```idris
||| routes : List Route
||| routes =
|||   [ route GET "/users/:id" $ \req, ps =>
|||       case param "id" ps of
|||         Just i => pure (jsonResponse statusOK (MkUser i))
|||         Nothing => pure (statusResponse statusNotFound)
|||   , route POST "/users" $ \req, ps => do
|||       Right u <- jsonBody {a = NewUser} req
|||         | Left bad => pure bad
|||       ...
|||   ]
|||
||| main : IO ()
||| main = ignore (serve (defaultServerConfig (Inet "0.0.0.0" 8080)) (router routes))
||| ```
|||
||| A pattern is a path whose segments are literal (`users`), captured
||| (`:id`, one segment) or the rest of the path (`*path`, last only).  The
||| segments of a request path are percent-decoded before they are compared
||| or captured (so `%2F` in a segment is a `/` in its value, and does not
||| split it).  The routes are tried in order and the first that matches
||| the method and the path wins; a `HEAD` request that no route has goes to
||| the `GET` route of the path (the server sends no body).  A path that some
||| route has with another method gets 405 with an `Allow` field, and one
||| that no route has 404.  A trailing `/` is a segment of its own: `/users/`
||| does not match `/users`.
module Network.HTTP.Router

import Data.ByteString
import Data.ByteString.Internal
import Data.List
import Data.List1
import Data.Maybe
import Data.String
import Language.JSON.Typed
import Network.HTTP.Internal.Bytes
import public Network.HTTP.Server
import Network.URI

%default covering

--------------------------------------------------------------------------
-- Patterns
--------------------------------------------------------------------------

||| A segment of a path pattern.
public export
data Segment
  = ||| This text (compared with the decoded segment of the request).
    Literal ByteString
  | ||| Any one segment, captured under this name.
    Capture String
  | ||| The rest of the path (decoded, may be empty), under this name.
    Rest String

||| The captured segments of a path, by name, in the order of the pattern.
public export
Params : Type
Params = List (String, String)

||| A handler of a route: the request and the captured segments.
public export
RouteHandler : Type
RouteHandler = Request -> Params -> IO Response

||| A route: a method, a pattern and a handler.
export
record Route where
  constructor MkRoute
  method : Method
  segments : List Segment
  handler : RouteHandler

slash : Bits8
slash = 47

-- The segments of a path (after its leading `/`).
pathSegments : ByteString -> List ByteString
pathSegments p =
  let p' = if lengthInt p > 0 && unsafeIndex p 0 == slash then dropInt 1 p else p in
  forget (split slash p')

||| The segments of a pattern such as `/users/:id/files/*path`.
export
parsePattern : String -> List Segment
parsePattern s = map seg (pathSegments (fromString s))
  where
    seg : ByteString -> Segment
    seg b = case unpack (toStringLossy b) of
              (':' :: name) => Capture (pack name)
              ('*' :: name) => Rest (pack name)
              _ => Literal b

||| A route of a method and a pattern (see `parsePattern`).
export
route : Method -> (pattern : String) -> RouteHandler -> Route
route m p h = MkRoute m (parsePattern p) h

||| A route of a method and segments made by hand.
export
routeSegments : Method -> List Segment -> RouteHandler -> Route
routeSegments = MkRoute

--------------------------------------------------------------------------
-- Matching
--------------------------------------------------------------------------

slashBS : ByteString
slashBS = "/"

-- Match the decoded segments of a path; the captures, the last first.
matchSegments : List Segment -> List ByteString -> Params -> Maybe Params
matchSegments [] [] acc = Just acc
matchSegments [] (_ :: _) _ = Nothing
matchSegments [Rest n] rest acc = Just ((n, toStringLossy (intercalate slashBS rest)) :: acc)
matchSegments (_ :: _) [] _ = Nothing
matchSegments (Literal l :: ps) (x :: xs) acc = if l == x then matchSegments ps xs acc else Nothing
matchSegments (Capture n :: ps) (x :: xs) acc = matchSegments ps xs ((n, toStringLossy x) :: acc)
matchSegments (Rest n :: ps) (x :: xs) acc = matchSegments ps xs ((n, toStringLossy x) :: acc)

||| The captured segments, if the pattern matches the decoded segments of a
||| path.
export
matchPath : List Segment -> List ByteString -> Maybe Params
matchPath ps xs = reverse <$> matchSegments ps xs []

||| The percent-decoded segments of a request path; `Nothing` if one of them
||| has a `%` that is not followed by two hexadecimal digits.
export
decodedSegments : ByteString -> Maybe (List ByteString)
decodedSegments p = go (pathSegments p) []
  where
    -- (a segment without `%` is itself; a loop rather than `traverse`, which
    -- allocates the closures of the applicative for each segment)
    go : List ByteString -> List ByteString -> Maybe (List ByteString)
    go [] acc = Just (reverse acc)
    go (s :: rest) acc =
      if findByteFrom 37 0 s < 0 then go rest (s :: acc)
      else case percentDecode s of
             Just d => go rest (d :: acc)
             Nothing => Nothing

-- The same method (without the dictionary of `Eq`).
methodTag : Method -> Int
methodTag GET = 0
methodTag HEAD = 1
methodTag POST = 2
methodTag PUT = 3
methodTag DELETE = 4
methodTag CONNECT = 5
methodTag OPTIONS = 6
methodTag TRACE = 7
methodTag PATCH = 8
methodTag (OtherMethod _) = 9

sameMethod : Method -> Method -> Bool
sameMethod a b = let t = methodTag a in t == methodTag b && (t < 9 || a == b)

data Found = Matched RouteHandler Params | WrongMethod (List Method) | NoRoute

-- The end of the segment of a path that starts at `i`: the next `/`, or
-- the end.
segmentEnd : ByteString -> Int -> Int
segmentEnd p i = let j = findByteFrom slash i p in if j < 0 then lengthInt p else j

noParams : Maybe Params
noParams = Just []

-- Match a pattern against a path that has no `%` (so that its segments
-- are their decoded selves), from the start of a segment at `i` (after
-- its `/`); the captures, the last first.  Does not allocate for literal
-- segments.
matchRaw : List Segment -> ByteString -> Int -> Params -> Maybe Params
matchRaw ps p i acc =
  let e = segmentEnd p i
      last = e >= lengthInt p
  in case ps of
       [] => Nothing
       [Rest n] => Just ((n, toStringLossy (dropInt i p)) :: acc)
       (Literal l :: rest) =>
         if lengthInt l == e - i && unsafeMatchesAt l p i
            then (if last then (case rest of
                                  [] => (case acc of [] => noParams; _ => Just acc)
                                  [Rest n] => Just ((n, "") :: acc)
                                  _ => Nothing)
                  else matchRaw rest p (assert_smaller i (e + 1)) acc)
            else Nothing
       (Capture n :: rest) => captured n rest e last
       (Rest n :: rest) => captured n rest e last
  where
    captured : String -> List Segment -> Int -> Bool -> Maybe Params
    captured n rest e last =
      let acc' = (n, toStringLossy (sliceFromTo i e p)) :: acc in
      if last then (case rest of
                      [] => Just acc'
                      [Rest m] => Just ((m, "") :: acc')
                      _ => Nothing)
      else matchRaw rest p (assert_smaller i (e + 1)) acc'

-- The routes of a path, in order (see `routerWith`): a path without `%`
-- is matched as it is, one with `%` by its decoded segments.
findRoute : Method -> ByteString -> Maybe (List ByteString) -> List Route -> Found
findRoute m path segs rs = go rs [] Nothing
  where
    match : List Segment -> Maybe Params
    match ps = case segs of
      Nothing =>
        -- (the leading `/` is not part of the first segment)
        case matchRaw ps path (if lengthInt path > 0 && unsafeIndex path 0 == slash then 1 else 0) [] of
          Just ps@(_ :: _ :: _) => Just (reverse ps)
          r => r
      Just ss => matchPath ps ss

    isHead : Method -> Bool
    isHead HEAD = True
    isHead _ = False

    isGet : Method -> Bool
    isGet GET = True
    isGet _ = False

    go : List Route -> List Method -> Maybe (RouteHandler, Params) -> Found
    go [] allowed headFallback =
      case headFallback of
        Just (h, ps) => Matched h ps
        Nothing => if null allowed then NoRoute else WrongMethod (reverse allowed)
    go (r :: rest) allowed fb =
      case match r.segments of
        Nothing => go rest allowed fb
        Just ps =>
          if sameMethod r.method m then Matched r.handler ps
          else if isHead m && isGet r.method && isNothing fb
            then go rest (r.method :: allowed) (Just (r.handler, ps))
            else go rest (if elem r.method allowed then allowed else r.method :: allowed) fb

commaSpace : ByteString
commaSpace = ", "

hAllow : ByteString
hAllow = "Allow"

||| A handler that routes requests, with a handler of its own for the paths
||| that no route has.
export
routerWith : (notFound : Handler) -> List Route -> Handler
routerWith notFound rs req = do
  -- (a bind first: an `IO` function whose body chooses between actions
  -- that are not all `do` blocks is compiled to one that returns a
  -- closure)
  () <- pure ()
  let path = req.path
  if findByteFrom 37 0 path < 0
     then dispatch (findRoute req.method path Nothing rs)
     else case decodedSegments path of
            Nothing => pure (statusResponse statusBadRequest)
            Just segs => dispatch (findRoute req.method path (Just segs) rs)
  where
    dispatch : Found -> IO Response
    dispatch (Matched h ps) = h req ps
    dispatch (WrongMethod ms) =
      pure (withHeader hAllow (intercalate commaSpace (map methodBytes ms))
              (statusResponse statusMethodNotAllowed))
    dispatch NoRoute = notFound req

||| A handler that routes requests: 404 for the paths that no route has,
||| 405 (with `Allow`) for the paths that routes have with other methods.
export
router : List Route -> Handler
router = routerWith (\_ => pure (statusResponse statusNotFound))

||| The value of a captured segment.
export
param : String -> Params -> Maybe String
param = lookup

--------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------

||| The pairs of the query of a request, form-decoded (see
||| `Network.URI.parseQuery`), as text (bytes that are not UTF-8 are
||| replaced).
export
queryParams : Request -> List (String, String)
queryParams req = case req.query of
  Nothing => []
  Just q => map (\(k, v) => (toStringLossy k, toStringLossy v)) (parseQuery q)

||| The value of the first pair of the query with a key.
export
queryParam : String -> Request -> Maybe String
queryParam k req = lookup k (queryParams req)

--------------------------------------------------------------------------
-- JSON
--------------------------------------------------------------------------

applicationJSON : ByteString
applicationJSON = "application/json"

hContentTypeCap : ByteString
hContentTypeCap = "Content-Type"

||| A response with a JSON body (`Content-Type: application/json`).
export
jsonResponse : ToJSON a => Status -> a -> Response
jsonResponse st x = respond st (addHeader hContentTypeCap applicationJSON emptyHeaders)
                              (BytesBody (toJSONBytes x))

||| A response with the JSON body `{"error": message}`.
export
jsonError : Status -> String -> Response
jsonError st msg = jsonResponse st (JObject [("error", JString msg)])

||| The body of a request decoded as JSON into a value: `Left` a response to
||| send instead if it cannot be: 413 for a body larger than the limit of
||| the server, 400 for a body that cannot be read, is not JSON or does not
||| fit the type, with `{"error": ..., "path": ...}` where the path (in the
||| notation of JSONPath, `$.items[2].name`) is the part that does not fit.
||| The content type of the request is not checked.
export
jsonBody : FromJSON a => Request -> IO (Either Response a)
jsonBody req = do
  Right bs <- requestBody req
    | Left BodyTooLarge => pure (Left (jsonError statusContentTooLarge "request body too large"))
    | Left e => pure (Left (jsonError statusBadRequest ("cannot read the request body: " ++ show e)))
  case fromJSONBytes bs of
    Right x => pure (Right x)
    Left (Mismatch path msg) =>
      pure (Left (jsonResponse statusBadRequest
                    (JObject [("error", JString msg), ("path", JString (showPath path))])))
    Left err => pure (Left (jsonError statusBadRequest (show err)))
