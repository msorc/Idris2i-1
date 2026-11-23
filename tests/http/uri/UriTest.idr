import Data.ByteString as BS
import Data.List
import Data.Maybe
import Network.HTTP.Types
import Network.URI

%default total

-- The components of a parse, and the text it prints back to.
showParse : Either URIError URI -> String
showParse (Left e) = "error " ++ show e
showParse (Right u) =
  "scheme=" ++ show u.scheme ++ " authority=" ++ show u.authority ++ " path=" ++ show u.path
  ++ " query=" ++ show u.query ++ " fragment=" ++ show u.fragment

uri : ByteString -> IO ()
uri bs = do
  let r = parseURI bs
  putStrLn (show bs ++ ": " ++ showParse r)
  case r of
    Right u => if renderURI u == bs then pure () else putStrLn ("  prints as " ++ show (renderURI u))
    Left _ => pure ()

-- RFC 3986 section 5.4.
base : URI
base = case parseURI "http://a/b/c/d;p?q" of
         Right u => u
         Left _ => MkURI Nothing Nothing "" Nothing Nothing

resolves : ByteString -> ByteString -> IO ()
resolves ref expected =
  case parseURIReference ref of
    Left e => putStrLn (show ref ++ ": error " ++ show e)
    Right r => let got = renderURI (resolve base r) in
               putStrLn (show ref ++ " -> " ++ show got ++ (if got == expected then "" else "  WRONG, expected " ++ show expected))

target : Method -> ByteString -> IO ()
target m bs = putStrLn (show m ++ " " ++ show bs ++ ": " ++ either (\e => "error " ++ show e) show (parseRequestTarget m bs))

allBytes : ByteString
allBytes = BS.pack (map cast [the Int 0 .. 255])

main : IO ()
main = do
  putStrLn "== RFC 3986 section 1.1.2"
  uri "ftp://ftp.is.co.za/rfc/rfc1808.txt"
  uri "http://www.ietf.org/rfc/rfc2396.txt"
  uri "ldap://[2001:db8::7]/c=GB?objectClass?one"
  uri "mailto:John.Doe@example.com"
  uri "news:comp.infosystems.www.servers.unix"
  uri "tel:+1-816-555-1212"
  uri "telnet://192.0.2.16:80/"
  uri "urn:oasis:names:specification:docbook:dtd:xml:4.1.2"
  putStrLn "== other URIs"
  uri "foo://example.com:8042/over/there?name=ferret#nose"
  uri "http://user:pa%20ss@host.example:8080/p%2Fq?x=%41#f"
  uri "http://host:/empty-port"
  uri "http://[v7.fe80::1]/future"
  uri "http://[::ffff:192.0.2.1]/mapped"
  uri "http://256.1.1.1/not-ipv4"
  uri "file:///etc/hosts"
  uri "http://h?#"
  uri "HTTP://Example.COM/"
  putStrLn "== malformed URIs"
  uri "//example.com/no-scheme"
  uri "1http://x/"
  uri "ht tp://x/"
  uri "http://x/a b"
  uri "http://x/%2"
  uri "http://x/%zz"
  uri "http://x/?q=\"\""
  uri "http://x/#a#b"
  uri "http://[::1/"
  uri "http://[::1]x/"
  uri "http://[1:2:3:4:5:6:7:8:9]/"
  uri "http://[fe80::1%25eth0]/"
  uri "http://a:b/"
  uri "http://a:70000/"
  uri "http://us er@x/"
  uri "http://x{y}/"
  uri "mailto://"
  putStrLn "== IPv6"
  let v6ok = ["::", "::1", "1::", "1:2:3:4:5:6:7:8", "1::8", "1:2:3:4:5:6::8", "1::3:4:5:6:7:8",
              "::2:3:4:5:6:7:8", "1:2:3:4:5:6:7::", "fe80::1:2", "::ffff:1.2.3.4", "1:2:3:4:5:6:1.2.3.4",
              "ABCD:ef01::", "0000:0000::"]
  let v6bad = ["", ":", ":::", "1:2:3:4:5:6:7", "1:2:3:4:5:6:7:8:9", "1::2::3", ":1::", "1::2:", "12345::",
               "g::", "1:2:3:4:5:6:7:1.2.3.4", "::1.2.3", "::1.2.3.256", "1:2:3:4:5:6:7:8::", "::1.2.3.4:5",
               "1:::2", "::01.2.3.4"]
  putStrLn ("valid: " ++ show (map isIPv6 v6ok))
  putStrLn ("invalid: " ++ show (map isIPv6 v6bad))
  putStrLn ("ipv4: " ++ show (map isIPv4 ["1.2.3.4", "255.255.255.255", "0.0.0.0", "256.0.0.1", "1.2.3", "01.2.3.4", "1.2.3.4.", "a.b.c.d"]))
  putStrLn "== RFC 3986 section 5.4.1"
  resolves "g:h" "g:h"
  resolves "g" "http://a/b/c/g"
  resolves "./g" "http://a/b/c/g"
  resolves "g/" "http://a/b/c/g/"
  resolves "/g" "http://a/g"
  resolves "//g" "http://g"
  resolves "?y" "http://a/b/c/d;p?y"
  resolves "g?y" "http://a/b/c/g?y"
  resolves "#s" "http://a/b/c/d;p?q#s"
  resolves "g#s" "http://a/b/c/g#s"
  resolves "g?y#s" "http://a/b/c/g?y#s"
  resolves ";x" "http://a/b/c/;x"
  resolves "g;x" "http://a/b/c/g;x"
  resolves "g;x?y#s" "http://a/b/c/g;x?y#s"
  resolves "" "http://a/b/c/d;p?q"
  resolves "." "http://a/b/c/"
  resolves "./" "http://a/b/c/"
  resolves ".." "http://a/b/"
  resolves "../" "http://a/b/"
  resolves "../g" "http://a/b/g"
  resolves "../.." "http://a/"
  resolves "../../" "http://a/"
  resolves "../../g" "http://a/g"
  putStrLn "== RFC 3986 section 5.4.2"
  resolves "../../../g" "http://a/g"
  resolves "../../../../g" "http://a/g"
  resolves "/./g" "http://a/g"
  resolves "/../g" "http://a/g"
  resolves "g." "http://a/b/c/g."
  resolves ".g" "http://a/b/c/.g"
  resolves "g.." "http://a/b/c/g.."
  resolves "..g" "http://a/b/c/..g"
  resolves "./../g" "http://a/b/g"
  resolves "./g/." "http://a/b/c/g/"
  resolves "g/./h" "http://a/b/c/g/h"
  resolves "g/../h" "http://a/b/c/h"
  resolves "g;x=1/./y" "http://a/b/c/g;x=1/y"
  resolves "g;x=1/../y" "http://a/b/c/y"
  resolves "g?y/./x" "http://a/b/c/g?y/./x"
  resolves "g?y/../x" "http://a/b/c/g?y/../x"
  resolves "g#s/./x" "http://a/b/c/g#s/./x"
  resolves "g#s/../x" "http://a/b/c/g#s/../x"
  resolves "http:g" "http:g"
  putStrLn "== dot segments"
  putStrLn (show (map removeDotSegments ["/a/b/c/./../../g", "mid/content=5/../6", "/..", "/.", ".", "..", "", "/a/b/..", "a/./b", "/a//b/../c", "/%2E%2E/a"]))
  putStrLn "== percent-encoding"
  putStrLn (show (map percentDecode ["abc", "a%20b", "%41%42%43", "%e2%82%AC", "%", "%4", "%4g", "a%%20", "100%"]))
  putStrLn (show (encodePathSegment "a b/c?d#e%f@g:h"))
  putStrLn (show (encodePath "/a b/c?d"))
  putStrLn (show (encodeQuery "a=1&b=2 3?/#"))
  putStrLn (show (encodeUserinfo "us er:p@ss"))
  putStrLn (show (encodePathSegment "\8364"))
  let codes = [encodePathSegment, encodePath, encodeQuery, encodeUserinfo, percentEncode (const True), percentEncode (const False)]
  putStrLn ("round trips over all bytes: " ++ show (map (\enc => percentDecode (enc allBytes) == Just allBytes) codes))
  putStrLn "== form data"
  putStrLn (show (parseQuery "a=1&b=2&a=3&&c&d=x+y%20z&e=%zz&=v&f=a=b&g%3D=%26"))
  putStrLn (show (parseQuery ""))
  putStrLn (show (formEncode [("name", "J\252rgen Doe"), ("q", "a+b=c&d"), ("x", ""), ("*-._~", "!")]))
  putStrLn ("form round trip: " ++ show (parseQuery (formEncode [("k k", "v&v"), ("bytes", allBytes)]) == [("k k", "v&v"), ("bytes", allBytes)]))
  putStrLn "== request targets"
  target GET "/"
  target GET "/where?q=now&x"
  target GET "/a%20b?c=%zz"
  target GET "/a b"
  target GET "http://www.example.org/pub/WWW/TheProject.html"
  target GET "http://www.example.org/a#frag"
  target GET "www.example.org:80"
  target GET "*"
  target OPTIONS "*"
  target CONNECT "www.example.com:80"
  target CONNECT "[::1]:443"
  target CONNECT "www.example.com"
  target CONNECT "user@www.example.com:80"
  target CONNECT "/"
  target POST ""
  putStrLn "== host fields"
  putStrLn (show (map (\h => either (\e => "error " ++ show e) show (parseHostField h))
                      ["example.com", "example.com:8080", "[::1]:80", "192.0.2.1", "user@x", "a b", "x:y", ""]))
