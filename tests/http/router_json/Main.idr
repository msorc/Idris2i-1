-- The router: literal and captured segments, the rest of a path, decoded
-- segments, 404 and 405 with Allow, HEAD served by the GET route, queries;
-- and the JSON helpers with derived instances (a decode error answered 400
-- with its path).
import Data.ByteString
import Data.List
import HttpTest
import Language.JSON.Derive
import Language.JSON.Typed
import Network.HTTP.Client
import Network.HTTP.Router
import System

%default covering
%language ElabReflection

record Item where
  constructor MkItem
  name : String
  qty : Int
  tags : List String

%hint
itemToJSON : ToJSON Item
itemToJSON = %runElab deriveToJSON defaultOptions

%hint
itemFromJSON : FromJSON Item
itemFromJSON = %runElab deriveFromJSON defaultOptions

routes : List Route
routes =
  [ route GET "/items/:id" $ \req, ps =>
      pure (textResponse statusOK ("item " ++ show (param "id" ps) ++ "\n"))
  , route DELETE "/items/:id" $ \req, ps =>
      pure (textResponse statusOK ("deleted " ++ show (param "id" ps) ++ "\n"))
  , route GET "/users/:user/files/*path" $ \req, ps =>
      pure (textResponse statusOK (show ps ++ "\n"))
  , route POST "/items" $ \req, ps => do
      Right item <- jsonBody {a = Item} req
        | Left bad => pure bad
      pure (jsonResponse statusCreated (the Item ({ qty $= (* 2) } item)))
  , route GET "/search" $ \req, ps =>
      pure (textResponse statusOK (show (queryParam "q" req) ++ " " ++ show (queryParams req) ++ "\n"))
  , route GET "/" $ \req, ps => pure (textResponse statusOK "root\n")
  ]

show1 : Client -> String -> Method -> String -> RequestBody -> IO ()
show1 c base m path body = do
  Right r <- fetch c m (base ++ path) (addHeader "Content-Type" "application/json" emptyHeaders) body
    | Left e => putStrLn "\{show m} \{path}: \{show e}"
  putStrLn "\{show m} \{path}: \{show r.status.code} allow=\{show (lookupHeader "allow" r.headers)} type=\{show (lookupHeader "content-type" r.headers)} \{show r.body}"

main : IO ()
main = do
  srv <- orDie "start" (startServer (defaultServerConfig (Inet "127.0.0.1" 0)) (router routes))
  let base = "http://\{show (serverAddress srv)}"
  c <- newClient defaultClientConfig
  show1 c base GET "/" NoRequestBody
  show1 c base GET "/items/42" NoRequestBody
  show1 c base GET "/items/a%2Fb%20c" NoRequestBody
  show1 c base DELETE "/items/7" NoRequestBody
  show1 c base HEAD "/items/7" NoRequestBody
  show1 c base PUT "/items/7" NoRequestBody
  show1 c base GET "/items" NoRequestBody
  show1 c base GET "/items/7/more" NoRequestBody
  show1 c base GET "/nothing" NoRequestBody
  show1 c base GET "/users/ann/files/a/b/c.txt" NoRequestBody
  show1 c base GET "/users/ann/files/" NoRequestBody
  show1 c base GET "/search?q=hello+world&x=%C3%A9" NoRequestBody
  show1 c base GET "/search" NoRequestBody
  show1 c base GET "/items/%zz" NoRequestBody
  show1 c base POST "/items" (RequestBytes "{\"name\": \"apple\", \"qty\": 3, \"tags\": [\"red\", \"fruit\"]}")
  show1 c base POST "/items" (RequestBytes "{\"name\": \"apple\", \"qty\": 3, \"tags\": [\"red\", 5]}")
  show1 c base POST "/items" (RequestBytes "{\"name\": \"apple\", \"tags\": []}")
  show1 c base POST "/items" (RequestBytes "{\"name\": ")
  show1 c base POST "/items" (RequestBytes "")
  stopServer srv 1000
