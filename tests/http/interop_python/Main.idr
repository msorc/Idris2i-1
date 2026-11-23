-- The client against `python3 -m http.server` (HTTP/1.0, bodies that end
-- with the connection, a redirect for a directory without its slash).
import Data.ByteString
import Data.List
import Data.String
import Network.HTTP.Client
import System

%default covering

main : IO ()
main = do
  [_, port] <- getArgs
    | _ => putStrLn "usage: main port"
  let base = "http://127.0.0.1:\{port}"
  c <- newClient defaultClientConfig
  Right r <- httpGet c (base ++ "/hello.txt")
    | Left e => putStrLn "GET /hello.txt: \{show e}"
  putStrLn "GET /hello.txt: \{show r.status.code} type=\{show (lookupHeader "content-type" r.headers)} \{show r.body}"
  Right r <- httpGet c (base ++ "/dir")
    | Left e => putStrLn "GET /dir: \{show e}"
  putStrLn "GET /dir (redirected to /dir/): \{show r.status.code} lists the file: \{show (isInfixOf "inner.txt" (toStringLossy r.body))} url ends with /dir/: \{show (isSuffixOf "/dir/" r.url)}"
  Right r <- httpGet c (base ++ "/missing")
    | Left e => putStrLn "GET /missing: \{show e}"
  putStrLn "GET /missing: \{show r.status.code}"
  Right r <- withResponse c GET (base ++ "/big.bin") emptyHeaders NoRequestBody (\resp => do
               Right b <- readAll resp.body 10000000
                 | Left e => pure (show e)
               pure "\{show resp.status.code} \{show (length b)} bytes")
    | Left e => putStrLn "GET /big.bin: \{show e}"
  putStrLn "GET /big.bin: \{r}"
  n <- connectionsOpened c
  putStrLn "connections (HTTP/1.0 closes each): \{show n}"
