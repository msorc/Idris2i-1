import Data.ByteString as BS
import Data.ByteString.Builder as B
import Data.List
import Data.String
import Network.HTTP.Types
import Network.HTTP.Parser
import Network.HTTP.Render

%default total

-- The outcome of a parse, as text.
outcome : Show a => Progress a -> String
outcome (NeedMore p) = "NeedMore after " ++ show (consumed p)
outcome (Done r rest) = "Done " ++ show r ++ " rest=" ++ show rest
outcome (Failed e) = "Failed " ++ show e ++ " (" ++ show (errorStatus e) ++ ")"

-- Feed the pieces one after the other, until the parser stops.  The rest
-- after the head is the rest of the piece and the pieces not fed.
feedAll : HeadParser a -> List ByteString -> Progress a
feedAll p [] = NeedMore p
feedAll p (x :: xs) = case feed p x of
                        NeedMore p' => feedAll p' xs
                        Done r rest => Done r (BS.concat (rest :: xs))
                        r => r

-- The input split at k.
splitAtK : Nat -> ByteString -> List ByteString
splitAtK k bs = [BS.take k bs, BS.drop k bs]

-- The input in pieces of one byte.
bytewise : ByteString -> List ByteString
bytewise bs = map BS.singleton (BS.unpack bs)

-- The input split in three at every pair of points (i <= j).
threeWays : ByteString -> List (List ByteString)
threeWays bs =
  let n = BS.length bs in
  [ [BS.take i bs, BS.take (minus j i) (BS.drop i bs), BS.drop j bs]
  | i <- [0 .. n], j <- [i .. n] ]

-- Does every way of splitting the input give the same outcome as the whole?
sameWhenSplit : Show a => HeadParser a -> ByteString -> String
sameWhenSplit p bs =
  let whole = outcome (feed p bs)
      ways = map (\k => splitAtK k bs) [0 .. BS.length bs] ++ [bytewise bs]
             ++ (if BS.length bs <= 80 then threeWays bs else [])
      bad = filter (\w => outcome (feedAll p w) /= whole) ways
  in case bad of
       [] => "same in " ++ show (length ways) ++ " splits"
       (w :: _) => "DIFFERENT for " ++ show w ++ ": " ++ outcome (feedAll p w)

req : Limits -> String -> ByteString -> IO ()
req l name bs = do
  putStrLn (name ++ ": " ++ outcome (feed (requestParser l) bs))
  putStrLn ("  " ++ sameWhenSplit (requestParser l) bs)

resp : String -> ByteString -> IO ()
resp name bs = do
  putStrLn (name ++ ": " ++ outcome (feed (responseParser defaultLimits) bs))
  putStrLn ("  " ++ sameWhenSplit (responseParser defaultLimits) bs)

-- The framing of a request head (it must parse).
framing : Limits -> String -> ByteString -> IO ()
framing l name bs = case feed (requestParser l) bs of
  Done r _ => putStrLn (name ++ ": " ++ either (\e => "Failed " ++ show e ++ " (" ++ show (errorStatus e) ++ ")") show (requestFraming l r))
  other => putStrLn (name ++ ": head " ++ outcome other)

respFraming : Method -> String -> ByteString -> IO ()
respFraming m name bs = case feed (responseParser defaultLimits) bs of
  Done r _ => putStrLn (name ++ ": " ++ either (\e => "Failed " ++ show e) show (responseFraming m r))
  other => putStrLn (name ++ ": head " ++ outcome other)

typical : ByteString
typical = "GET /static/js/app.bundle.js?v=1234567 HTTP/1.1\r\nHost: www.example.com\r\nConnection: keep-alive\r\nsec-ch-ua: \"Chromium\";v=\"124\", \"Google Chrome\";v=\"124\"\r\nUser-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36\r\nAccept: */*\r\nSec-Fetch-Site: same-origin\r\nReferer: https://www.example.com/index.html\r\nAccept-Encoding: gzip, deflate, br\r\nAccept-Language: en-US,en;q=0.9\r\n\r\n"

small : Limits
small = MkLimits 30 30 3 120 (Just 10)

main : IO ()
main = do
  putStrLn "== valid requests"
  req defaultLimits "minimal" "GET / HTTP/1.1\r\nHost: x\r\n\r\n"
  req defaultLimits "typical" typical
  req defaultLimits "values" "POST /submit?a=b HTTP/1.1\r\nHost:x\r\nX-Empty:\r\nX-Spaces: \t a  b \t\r\nX-Obs-Text: caf\233\r\nX-Dup: 1\r\nx-dup: 2\r\n\r\n"
  req defaultLimits "http/1.0 without host" "GET /old HTTP/1.0\r\nAccept: *\r\n\r\n"
  req defaultLimits "other method" "PROPFIND /dav HTTP/1.1\r\nHost: x\r\n\r\n"
  req defaultLimits "lower-case method is a token" "get / HTTP/1.1\r\nHost: x\r\n\r\n"
  req defaultLimits "leading empty lines" "\r\n\r\nGET / HTTP/1.1\r\nHost: x\r\n\r\n"
  req defaultLimits "minor version 9" "GET / HTTP/1.9\r\nHost: x\r\n\r\n"
  req defaultLimits "absolute form" "GET http://example.com/a?b HTTP/1.1\r\nHost: example.com\r\n\r\n"
  req defaultLimits "incomplete" "GET / HTTP/1.1\r\nHost: x\r\n"

  putStrLn "== malformed requests and smuggling shapes"
  req defaultLimits "space before colon" "GET / HTTP/1.1\r\nHost : x\r\n\r\n"
  req defaultLimits "tab before colon" "GET / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding\t: chunked\r\n\r\n"
  req defaultLimits "obs-fold" "GET / HTTP/1.1\r\nHost: x\r\nX-A: a\r\n b\r\n\r\n"
  req defaultLimits "whitespace before first field" "GET / HTTP/1.1\r\n Host: x\r\n\r\n"
  req defaultLimits "bare CR in value" "GET / HTTP/1.1\r\nHost: x\r\nX-A: a\rb\r\n\r\n"
  req defaultLimits "bare CR ending the request line" "GET / HTTP/1.1\rHost: x\r\n\r\n"
  req defaultLimits "bare LF ending a field" "GET / HTTP/1.1\r\nHost: x\n\r\n"
  req defaultLimits "bare LF ending the request line" "GET / HTTP/1.1\nHost: x\r\n\r\n"
  req defaultLimits "bare LF ending the head" "GET / HTTP/1.1\r\nHost: x\r\n\n"
  req defaultLimits "NUL in value" ("GET / HTTP/1.1\r\nHost: x\r\nX-A: a" <+> BS.singleton 0 <+> "b\r\n\r\n")
  req defaultLimits "control in value" "GET / HTTP/1.1\r\nHost: x\r\nX-A: a\1b\r\n\r\n"
  req defaultLimits "DEL in value" "GET / HTTP/1.1\r\nHost: x\r\nX-A: a\127b\r\n\r\n"
  req defaultLimits "non-token in name" "GET / HTTP/1.1\r\nHost: x\r\nX(A): b\r\n\r\n"
  req defaultLimits "non-ASCII in name" "GET / HTTP/1.1\r\nHost: x\r\nX\233: b\r\n\r\n"
  req defaultLimits "empty name" "GET / HTTP/1.1\r\nHost: x\r\n: b\r\n\r\n"
  req defaultLimits "no colon" "GET / HTTP/1.1\r\nHost: x\r\nX-A\r\n\r\n"
  req defaultLimits "non-token method" "GE(T / HTTP/1.1\r\nHost: x\r\n\r\n"
  req defaultLimits "two spaces after method" "GET  / HTTP/1.1\r\nHost: x\r\n\r\n"
  req defaultLimits "leading space" " GET / HTTP/1.1\r\nHost: x\r\n\r\n"
  req defaultLimits "HTTP/0.9 request line" "GET /\r\n\r\n"
  req defaultLimits "space in target" "GET /a b HTTP/1.1\r\nHost: x\r\n\r\n"
  req defaultLimits "non-ASCII target" "GET /caf\233 HTTP/1.1\r\nHost: x\r\n\r\n"
  req defaultLimits "trailing space after version" "GET / HTTP/1.1 \r\nHost: x\r\n\r\n"
  req defaultLimits "lower-case version" "GET / http/1.1\r\nHost: x\r\n\r\n"
  req defaultLimits "short version" "GET / HTTP/1\r\nHost: x\r\n\r\n"
  req defaultLimits "version 2.0" "GET / HTTP/2.0\r\nHost: x\r\n\r\n"
  req defaultLimits "version 0.9" "GET / HTTP/0.9\r\nHost: x\r\n\r\n"
  req defaultLimits "missing host" "GET / HTTP/1.1\r\nAccept: */*\r\n\r\n"
  req defaultLimits "two hosts" "GET / HTTP/1.1\r\nHost: a\r\nhost: b\r\n\r\n"

  putStrLn "== framing of requests"
  framing defaultLimits "no body" "GET / HTTP/1.1\r\nHost: x\r\n\r\n"
  framing defaultLimits "content-length" "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 42\r\n\r\n"
  framing defaultLimits "content-length 0" "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n"
  framing defaultLimits "leading zeros" "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 007\r\n\r\n"
  framing defaultLimits "same list" "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 5, 5\r\n\r\n"
  framing defaultLimits "same fields" "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\ncontent-length: 5\r\n\r\n"
  framing defaultLimits "different list" "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 5, 6\r\n\r\n"
  framing defaultLimits "different fields" "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\n"
  framing defaultLimits "plus sign" "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: +5\r\n\r\n"
  framing defaultLimits "negative" "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: -1\r\n\r\n"
  framing defaultLimits "hexadecimal" "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 0x5\r\n\r\n"
  framing defaultLimits "empty" "POST / HTTP/1.1\r\nHost: x\r\nContent-Length:\r\n\r\n"
  framing defaultLimits "overflow" "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 99999999999999999999\r\n\r\n"
  framing defaultLimits "chunked" "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n"
  framing defaultLimits "chunked in capitals" "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: CHUNKED\r\n\r\n"
  framing defaultLimits "CL and TE" "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n"
  framing defaultLimits "TE and CL" "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n"
  framing defaultLimits "TE not chunked" "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip\r\n\r\n"
  framing defaultLimits "TE chunked not last" "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked, gzip\r\n\r\n"
  framing defaultLimits "TE chunked twice" "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked, chunked\r\n\r\n"
  framing defaultLimits "TE chunked in two fields" "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: chunked\r\n\r\n"
  framing defaultLimits "TE gzip then chunked" "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip, chunked\r\n\r\n"
  framing defaultLimits "TE gzip then chunked in two fields" "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip\r\nTransfer-Encoding: chunked\r\n\r\n"
  framing defaultLimits "TE empty element" "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: , chunked\r\n\r\n"
  framing defaultLimits "TE empty" "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding:\r\n\r\n"
  framing defaultLimits "TE chunked with junk" "POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: xchunked\r\n\r\n"
  framing defaultLimits "TE in HTTP/1.0" "POST / HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n"
  framing small "content too large" "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 11\r\n\r\n"
  framing small "content at the limit" "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 10\r\n\r\n"

  putStrLn "== limits"
  req small "request line at the limit" "GET /0123456789012345 HTTP/1.1\r\nHost: x\r\n\r\n"
  req small "request line too long" "GET /01234567890123456 HTTP/1.1\r\nHost: x\r\n\r\n"
  req small "request line too long, unfinished" "GET /0123456789012345678901234567890123456789"
  req small "field line at the limit" "GET / HTTP/1.1\r\nHost: x\r\nX: 012345678901234567890123456\r\n\r\n"
  req small "field line too long" "GET / HTTP/1.1\r\nHost: x\r\nX: 0123456789012345678901234567\r\n\r\n"
  req small "field line too long, unfinished" "GET / HTTP/1.1\r\nHost: x\r\nX: 0123456789012345678901234567890123"
  req small "three fields" "GET / HTTP/1.1\r\nHost: x\r\nA: 1\r\nB: 2\r\n\r\n"
  req small "four fields" "GET / HTTP/1.1\r\nHost: x\r\nA: 1\r\nB: 2\r\nC: 3\r\n\r\n"
  req ({ maxHeaders := 100 } small) "head too large" "GET / HTTP/1.1\r\nHost: x\r\nA: 0123456789\r\nB: 0123456789\r\nC: 0123456789\r\nD: 0123456789\r\nE: 0123456789\r\nF: 0123456789\r\nG: 0123456789\r\n\r\n"
  req ({ maxHeaders := 100 } small) "head too large, unfinished" "GET / HTTP/1.1\r\nHost: x\r\nA: 0123456789\r\nB: 0123456789\r\nC: 0123456789\r\nD: 0123456789\r\nE: 0123456789\r\nF: 0123456789\r\nG: 012"
  req ({ maxHeaders := 100 } small) "head too large by empty lines" "\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\n\r\nGET"

  putStrLn "== pipelining"
  let two = "GET /1 HTTP/1.1\r\nHost: x\r\n\r\nGET /2 HTTP/1.1\r\nHost: y\r\n\r\n"
  case feed (requestParser defaultLimits) two of
    Done r1 rest => do
      putStrLn ("first: " ++ show r1 ++ " rest " ++ show rest)
      putStrLn ("second: " ++ outcome (feed (requestParser defaultLimits) rest))
    other => putStrLn (outcome other)
  let withBody = "POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nhelloGET /b HTTP/1.1\r\nHost: x\r\n\r\n"
  case feed (requestParser defaultLimits) withBody of
    Done r rest => case requestFraming defaultLimits r of
      Right (ContentLength n) => do
        putStrLn ("body: " ++ show (BS.take (cast n) rest))
        putStrLn ("next: " ++ outcome (feed (requestParser defaultLimits) (BS.drop (cast n) rest)))
      other => putStrLn ("framing " ++ show other)
    other => putStrLn (outcome other)
  -- The rest after a head split across pieces is the rest of the last piece.
  putStrLn ("split pipelined: " ++ outcome (feedAll (requestParser defaultLimits) ["GET /1 HTTP/1.1\r\nHo", "st: x\r\n\r", "\nGET /2"]))

  putStrLn "== responses"
  resp "ok" "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nContent-Type: text/plain\r\n\r\nhello"
  resp "not found" "HTTP/1.1 404 Not Found\r\n\r\n"
  resp "no reason" "HTTP/1.1 204\r\nDate: x\r\n\r\n"
  resp "empty reason" "HTTP/1.1 200 \r\n\r\n"
  resp "http/1.0" "HTTP/1.0 302 Found\r\nLocation: /x\r\n\r\n"
  resp "reason with obs-text" "HTTP/1.1 200 \231a va\r\n\r\n"
  resp "two-digit code" "HTTP/1.1 20 OK\r\n\r\n"
  resp "four-digit code" "HTTP/1.1 2000 OK\r\n\r\n"
  resp "code starting with 0" "HTTP/1.1 099 X\r\n\r\n"
  resp "HTTP/2" "HTTP/2 200 OK\r\n\r\n"
  resp "version 2.0" "HTTP/2.0 200 OK\r\n\r\n"
  resp "bare LF" "HTTP/1.1 200 OK\n\r\n"
  resp "control in reason" "HTTP/1.1 200 O\1K\r\n\r\n"

  putStrLn "== framing of responses"
  respFraming GET "content-length" "HTTP/1.1 200 OK\r\nContent-Length: 12\r\n\r\n"
  respFraming HEAD "to HEAD" "HTTP/1.1 200 OK\r\nContent-Length: 12\r\n\r\n"
  respFraming GET "204" "HTTP/1.1 204 No Content\r\n\r\n"
  respFraming GET "304" "HTTP/1.1 304 Not Modified\r\nContent-Length: 12\r\n\r\n"
  respFraming GET "100" "HTTP/1.1 100 Continue\r\n\r\n"
  respFraming CONNECT "CONNECT 200" "HTTP/1.1 200 OK\r\n\r\n"
  respFraming CONNECT "CONNECT 407" "HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 3\r\n\r\n"
  respFraming GET "chunked" "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
  respFraming GET "TE not chunked" "HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip\r\n\r\n"
  respFraming GET "CL and TE" "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 3\r\n\r\n"
  respFraming GET "until close" "HTTP/1.1 200 OK\r\n\r\n"
  respFraming GET "bad CL" "HTTP/1.1 200 OK\r\nContent-Length: 1x\r\n\r\n"

  putStrLn "== connection"
  let headOf : ByteString -> Maybe RequestHead
      headOf bs = case feed (requestParser defaultLimits) bs of
                    Done r _ => Just r
                    _ => Nothing
  let persist = \bs => map (\r => isPersistent r.version r.headers) (headOf bs)
  putStrLn ("1.1: " ++ show (persist "GET / HTTP/1.1\r\nHost: x\r\n\r\n"))
  putStrLn ("1.1 close: " ++ show (persist "GET / HTTP/1.1\r\nHost: x\r\nConnection: keep-alive, Close\r\n\r\n"))
  putStrLn ("1.0: " ++ show (persist "GET / HTTP/1.0\r\n\r\n"))
  putStrLn ("1.0 keep-alive: " ++ show (persist "GET / HTTP/1.0\r\nConnection: Keep-Alive\r\n\r\n"))
  putStrLn ("expect: " ++ show (map expectsContinue (headOf "PUT / HTTP/1.1\r\nHost: x\r\nExpect: 100-Continue\r\n\r\n")))

  putStrLn "== headers"
  case headOf "GET / HTTP/1.1\r\nHost: x\r\nAccept: a\r\nACCEPT: b\r\nX: y\r\n\r\n" of
    Just r => do
      putStrLn ("lookup: " ++ show (lookupHeader "accept" r.headers) ++ " " ++ show (lookupHeader "missing" r.headers))
      putStrLn ("all: " ++ show (lookupHeaders "Accept" r.headers))
      putStrLn ("combined: " ++ show (combinedHeader "accept" r.headers))
      putStrLn ("set: " ++ show (setHeader "accept" "c" r.headers))
      putStrLn ("remove: " ++ show (removeHeader "ACCEPT" r.headers))
      putStrLn ("add: " ++ show (addHeader "Z" "1" r.headers))
    Nothing => putStrLn "no head"
  putStrLn ("valid value: " ++ show (map isValidHeaderValue ["ok", "", " lead", "trail\t", "a\r\nb", "caf\233"]))
  putStrLn ("valid name: " ++ show (map isValidHeaderName ["X-Ok", "", "a b", "a:b"]))

  putStrLn "== rendering"
  let r1 = MkRequestHead GET "/x?y" http11 (headersFromPairs [("Host", "example.com"), ("Accept", "*/*")])
  putStrLn (show (B.toByteString (renderRequestHead r1)))
  putStrLn ("round trip: " ++ show (map (== r1) (headOf (B.toByteString (renderRequestHead r1)))))
  let r2 = MkRequestHead (OtherMethod "PURGE") "/" http10 emptyHeaders
  putStrLn (show (B.toByteString (renderRequestHead r2)))
  let s1 = MkResponseHead http11 statusNotFound (headersFromPairs [("Content-Length", "0")])
  putStrLn (show (B.toByteString (renderResponseHead s1)))
  putStrLn ("round trip: " ++ outcome (feed (responseParser defaultLimits) (B.toByteString (renderResponseHead s1))))
  putStrLn (show (B.toByteString (renderResponseHead (MkResponseHead http10 (statusFromCode 299) emptyHeaders))))
  putStrLn ("statuses: " ++ show (map statusFromCode [100, 200, 404, 418, 431, 505]))
  putStrLn ("methods: " ++ show (map methodFromBytes ["GET", "HEAD", "POST", "PUT", "DELETE", "CONNECT", "OPTIONS", "TRACE", "PATCH", "Get", "BREW"]))
