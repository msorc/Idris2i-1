-- Helpers of the tests of HTTPS: TLS contexts made from the throwaway
-- certificates of ../../tls/gencerts.sh, and checksums of bodies.
module HttpsTest

import Data.ByteString
import Data.List
import Network.HTTP.Client
import Network.HTTP.Server
import Network.HTTP.TLS
import Network.TLS
import System

%default covering

export
die : String -> IO a
die msg = do putStrLn msg; exitFailure

||| A context of servers with the credentials `name`.pem and `name`.key of
||| the directory of certificates, offering these protocols with ALPN.
export
serverContext : (certs : String) -> (name : String) -> (alpn : List String) -> IO ServerContext
serverContext certs name alpn = do
  let creds = credentialFiles (certs ++ "/" ++ name ++ ".pem") (certs ++ "/" ++ name ++ ".key")
  Right ctx <- newServerContext ({ alpn := alpn } (Network.TLS.serverConfig creds))
    | Left e => die "server context: \{show e}"
  pure ctx

||| A context of clients that trust the test authority, offering these
||| protocols with ALPN.
export
clientContext : (certs : String) -> (alpn : List String) -> IO ClientContext
clientContext certs alpn = do
  Right ctx <- newClientContext ({ trust := [CAFile (certs ++ "/ca.pem")], alpn := alpn }
                                   Network.TLS.defaultClientConfig)
    | Left e => die "client context: \{show e}"
  pure ctx

||| A client of `https://` URLs with a context.
export
httpsClient : ClientContext -> IO Client
httpsClient ctx = newClient (httpsClientConfig ctx Network.HTTP.Client.defaultClientConfig)

||| A body of `n` bytes that are not all the same.
export
bigBody : Nat -> ByteString
bigBody n =
  let piece = fromString (concatMap (\i => show i ++ ",") [the Int 1 .. 1000]) in
  take n (concat (List.replicate (S (cast (cast {to = Int} n `div` cast (length piece)))) piece))

||| The length and a hash of bytes.
export
checksum : ByteString -> String
checksum bs = "\{show (length bs)} bytes, hash \{show (Data.ByteString.foldl (\h, b => (h * 31 + cast b) `mod` 1000000007) (the Int 7) bs)}"
