-- The Idris benchmark server over HTTPS: the routes of Main.idr, on the
-- port given as the argument, with a certificate and its key.
import Network.HTTP.Router
import Network.HTTP.TLS
import Network.TLS
import Routes
import System

%default covering

main : IO ()
main = do
  [_, port, cert, key] <- getArgs
    | _ => putStrLn "usage: server port cert key"
  Right ctx <- newServerContext ({ alpn := ["h2", "http/1.1"] }
                                   (Network.TLS.serverConfig (credentialFiles cert key)))
    | Left e => putStrLn (show e)
  let base = { maxConnections := 100000, idleTimeout := 600000 }
             (defaultServerConfig (Inet "127.0.0.1" (cast port)))
  (cfg, _) <- httpsServerConfig ctx base
  Right () <- serve cfg (router routes)
    | Left e => putStrLn (show e)
  pure ()
