-- Drives the sample web service (samples/webservice) through its routes.
import Data.ByteString
import Network.HTTP.Client
import System

%default covering

step : Client -> String -> Method -> String -> RequestBody -> IO ()
step c base m path body = do
  Right r <- fetch c m (base ++ path) emptyHeaders body
    | Left e => putStrLn "\{show m} \{path}: \{show e}"
  putStrLn "\{show m} \{path}: \{show r.status.code} \{toStringLossy r.body}"

main : IO ()
main = do
  [_, port] <- getArgs
    | _ => putStrLn "usage: client port"
  let base = "http://127.0.0.1:\{port}"
  c <- newClient defaultClientConfig
  step c base GET "/health" NoRequestBody
  step c base POST "/todos" (RequestBytes "{\"title\": \"write the docs\"}")
  step c base POST "/todos" (RequestBytes "{\"title\": \"run the benchmark\", \"done\": true}")
  step c base GET "/todos" NoRequestBody
  step c base GET "/todos?done=false" NoRequestBody
  step c base PUT "/todos/1" (RequestBytes "{\"title\": \"write the docs\", \"done\": true}")
  step c base GET "/todos/1" NoRequestBody
  step c base DELETE "/todos/2" NoRequestBody
  step c base GET "/todos/2" NoRequestBody
  step c base GET "/todos/x" NoRequestBody
  step c base POST "/todos" (RequestBytes "{\"done\": true}")
  step c base POST "/todos" (RequestBytes "not json")
  step c base PATCH "/todos/1" NoRequestBody
