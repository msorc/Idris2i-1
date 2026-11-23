||| The sample web service of Main.idr over HTTPS, with the `http-tls`
||| library (built with the `tls` library, when OpenSSL 3 is there).
|||
|||     idris2 --build webservice-https.ipkg
|||     ./build/exec/webservice-https 8443 cert.pem key.pem
|||
||| The certificate file has the certificate of the server first, then the
||| intermediate ones.  A certificate for a test, valid for 30 days:
|||
|||     openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
|||       -keyout key.pem -out cert.pem -days 30 -subj /CN=localhost \
|||       -addext subjectAltName=DNS:localhost,IP:127.0.0.1
|||     curl --cacert cert.pem https://localhost:8443/todos
module Https

import Data.IORef
import Network.HTTP.Router
import Network.HTTP.TLS
import Network.TLS
import System
import Todos

%default covering

main : IO ()
main = do
  [_, p, cert, key] <- getArgs
    | _ => do putStrLn "usage: webservice-https PORT CERT KEY"
              exitFailure
  let port = the Int (cast p)
  -- HTTP/1.1 is offered with ALPN, as clients expect from a server that
  -- has one protocol
  Right ctx <- newServerContext ({ alpn := ["http/1.1"] }
                                   (Network.TLS.serverConfig (credentialFiles cert key)))
    | Left e => do putStrLn "cannot use the certificate: \{show e}"
                   exitFailure
  store <- newStore
  (cfg, _) <- httpsServerConfig ctx ({ accessLog := Just logRequest }
                                       (defaultServerConfig (Inet "127.0.0.1" port)))
  Right srv <- startServer cfg (router (routes store))
    | Left e => do putStrLn "cannot listen on port \{show port}: \{show e}"
                   exitFailure
  runUntilInterrupted srv
