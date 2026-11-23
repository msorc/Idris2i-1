-- The Idris benchmark server: GET /hello and POST /json (decode a record,
-- modify it, encode it), on the port given as the argument.
import Network.HTTP.Router
import Routes
import System

%default covering

main : IO ()
main = do
  [_, port] <- getArgs
    | _ => putStrLn "usage: server port"
  let cfg = { maxConnections := 100000, idleTimeout := 600000 }
            (defaultServerConfig (Inet "127.0.0.1" (cast port)))
  Right () <- serve cfg (router routes)
    | Left e => putStrLn (show e)
  pure ()
