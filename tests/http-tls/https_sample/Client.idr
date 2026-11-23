-- Drives the sample web service over HTTPS (samples/webservice/Https.idr)
-- through its routes.
import Data.ByteString
import HttpsTest
import Network.HTTP.Client
import Network.TLS
import System

%default covering

step : Client -> String -> Method -> String -> RequestBody -> IO ()
step c base m path body = do
  Right r <- fetch c m (base ++ path) emptyHeaders body
    | Left e => putStrLn "\{show m} \{path}: \{show e}"
  putStrLn "\{show m} \{path}: \{show r.status.code} \{toStringLossy r.body}"

main : IO ()
main = do
  [_, certs, port] <- getArgs
    | _ => putStrLn "usage: client certs port"
  let base = "https://localhost:\{port}"
  c <- httpsClient !(clientContext certs [])
  step c base GET "/health" NoRequestBody
  step c base POST "/todos" (RequestBytes "{\"title\": \"write the docs\"}")
  step c base POST "/todos" (RequestBytes "{\"title\": \"run the benchmark\", \"done\": true}")
  step c base GET "/todos" NoRequestBody
  step c base PUT "/todos/1" (RequestBytes "{\"title\": \"write the docs\", \"done\": true}")
  step c base DELETE "/todos/2" NoRequestBody
  step c base GET "/todos/2" NoRequestBody
  step c base POST "/todos" (RequestBytes "not json")
  putStrLn "connections: \{show !(connectionsOpened c)}"
