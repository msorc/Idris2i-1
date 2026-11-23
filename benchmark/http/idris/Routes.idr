-- The routes of the Idris benchmark servers (Main.idr over HTTP,
-- Https.idr over HTTPS): GET /hello and POST /json (decode a record, modify
-- it, encode it).
module Routes

import Data.ByteString
import Language.JSON.Derive
import Language.JSON.Typed
import Network.HTTP.Router
import System

%default covering
%language ElabReflection

public export
record Item where
  constructor MkItem
  id : Int
  name : String
  price : Double
  quantity : Int
  tags : List String
  active : Bool
  owner : String

%hint
itemToJSON : ToJSON Item
itemToJSON = %runElab deriveToJSON defaultOptions

%hint
itemFromJSON : FromJSON Item
itemFromJSON = %runElab deriveFromJSON defaultOptions

hello : Response
hello = textResponse statusOK "Hello, World!"

export
routes : List Route
routes =
  [ route GET "/hello" $ \_, _ => pure hello
  , route POST "/json" $ \req, _ => do
      Right it <- jsonBody {a = Item} req
        | Left bad => pure bad
      pure (jsonResponse statusOK (the Item ({ quantity $= (* 2), active $= not } it)))
  ]

