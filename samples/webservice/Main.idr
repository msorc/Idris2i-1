||| A small JSON web service: a list of things to do, kept in memory.
|||
|||     GET    /health          "ok"
|||     GET    /todos           every item (`?done=true` or `false` to filter)
|||     POST   /todos           a new item from {"title": ..., "done": ...}
|||     GET    /todos/:id       one item
|||     PUT    /todos/:id       replace an item
|||     DELETE /todos/:id       remove an item
|||
||| Build and run it (see "Writing a web service" in the documentation):
|||
|||     idris2i-1 --build webservice.ipkg
|||     ./build/exec/webservice 8080
|||
||| It stops gracefully on SIGINT (Ctrl-C): it stops accepting, lets the
||| requests in progress finish, and exits.  The routes are in Todos.idr;
||| Https.idr serves them over HTTPS.
module Main

import Data.IORef
import Network.HTTP.Router
import System
import Todos

%default covering

main : IO ()
main = do
  args <- getArgs
  let port = case args of
               (_ :: p :: _) => cast p
               _ => 8080
  store <- newStore
  let cfg = { accessLog := Just logRequest } (defaultServerConfig (Inet "127.0.0.1" port))
  Right srv <- startServer cfg (router (routes store))
    | Left e => do putStrLn "cannot listen on port \{show port}: \{show e}"
                   exitFailure
  runUntilInterrupted srv
