-- What a TLS client and a TLS server see when the handshake goes wrong or
-- negotiates something: verification failures (unknown authority, wrong
-- name, expired), the ways to turn verification off, ALPN, SNI, client
-- certificates, deadlines against a silent peer, a clean close and an
-- abrupt one, and the errors of configurations.
import Data.Buffer
import Data.List
import Data.Maybe
import Data.String
import Network.Socket.Async
import Network.TLS
import System
import System.Concurrency
import System.File

seconds : Int -> Int
seconds n = n * 1000000000

-- A server on a new port that takes one connection, runs the handshake,
-- then `act`, and puts what happened in the channel.
covering
serveOnce : ServerContext -> (TLSSocket -> IO String) -> IO (SockAddr, Channel String)
serveOnce ctx act = do
  ch <- makeChannel
  Right l <- listenOn (Inet "127.0.0.1" 0) 8
    | Left e => do channelPut ch "listen: \{show e}"; pure (Inet "127.0.0.1" 0, ch)
  Right addr <- localAddress l
    | Left e => do channelPut ch "localAddress: \{show e}"; pure (Inet "127.0.0.1" 0, ch)
  _ <- fork $ do
    Right sock <- Network.Socket.Async.accept l Nothing
      | Left e => channelPut ch "accept: \{show e}"
    ignore (Network.Socket.Async.close l)
    d <- deadlineIn (seconds 5)
    Right s <- Network.TLS.accept ctx sock (Just d)
      | Left e => channelPut ch (show e)
    msg <- act s
    ignore (Network.TLS.close s)
    channelPut ch msg
  pure (addr, ch)

covering
clientTo : ClientContext -> String -> SockAddr -> (TLSSocket -> IO String) -> IO String
clientTo ctx host addr act = do
  Right sock <- Network.Socket.Async.connect addr Nothing
    | Left e => pure "connect: \{show e}"
  d <- deadlineIn (seconds 5)
  Right s <- Network.TLS.connect ctx host sock (Just d)
    | Left e => pure (show e)
  msg <- act s
  ignore (Network.TLS.close s)
  pure msg

covering
scenario : String -> ServerContext -> ClientContext -> (host : String) ->
           (client : TLSSocket -> IO String) -> (server : TLSSocket -> IO String) -> IO ()
scenario title sctx cctx host cact sact = do
  (addr, ch) <- serveOnce sctx sact
  c <- clientTo cctx host addr cact
  s <- channelGet ch
  putStrLn "\{title}\n  client: \{c}\n  server: \{s}"

ok : TLSSocket -> IO String
ok s = do v <- tlsVersion s
          pure "ok, \{v}"

alpnOf : TLSSocket -> IO String
alpnOf s = do a <- alpnSelected s
              pure "ALPN \{show a}"

peerOf : TLSSocket -> IO String
peerOf s = do Just c <- peerCertificate s
                | Nothing => pure "no certificate from the peer"
              pure "peer \{c.subject} \{show c.altNames}"

sniOf : TLSSocket -> IO String
sniOf s = do n <- serverName s
             pure "SNI \{show n}"

-- The client reads: the server's rejection of a client certificate comes
-- after the client's handshake with TLS 1.3.
covering
readOne : TLSSocket -> IO String
readOne s = do
  Just buf <- newBuffer 16
    | Nothing => pure "newBuffer"
  Right n <- recv s buf 0 16 Nothing
    | Left e => pure "read: \{show e}"
  pure "read \{show n} bytes: \{!(getString buf 0 n)}"

covering
readTwice : TLSSocket -> IO String
readTwice s = do
  Just buf <- newBuffer 16
    | Nothing => pure "newBuffer"
  Right n <- recvExactly s buf 0 3 Nothing
    | Left e => pure "read: \{show e}"
  got <- getString buf 0 n
  r <- recv s buf 0 16 Nothing
  pure "read \{show got}, then \{show r}"

covering
sayBye : (abrupt : Bool) -> TLSSocket -> IO String
sayBye abrupt s = do
  Just buf <- newBuffer 3
    | Nothing => pure "newBuffer"
  setString buf 0 "bye"
  Right () <- sendAll s buf 0 3 Nothing
    | Left e => pure "send: \{show e}"
  when abrupt $ abort s
  pure (if abrupt then "sent bye, closed without close_notify" else "sent bye, closed")

covering
sayHi : TLSSocket -> IO String
sayHi s = do
  Just buf <- newBuffer 2
    | Nothing => pure "newBuffer"
  setString buf 0 "hi"
  Right () <- sendAll s buf 0 2 Nothing
    | Left e => pure "send: \{show e}"
  pure "sent hi"

bad : ServerConfig -> IO ()
bad cfg = do r <- newServerContext cfg
             putStrLn (either show (const "made") r)

server : String -> String -> Credentials
server certs name = credentialFiles (certs ++ "/" ++ name ++ ".pem") (certs ++ "/" ++ name ++ ".key")

covering
main : IO ()
main = do
  [_, certs] <- getArgs
    | _ => putStrLn "usage: main <certs>"
  let ca = CAFile (certs ++ "/ca.pem")
      trusting = { trust := [ca] } defaultClientConfig
  Right good <- newServerContext (serverConfig (server certs "server"))
    | Left e => putStrLn "server context: \{show e}"
  Right rogue <- newServerContext (serverConfig (server certs "rogue"))
    | Left e => putStrLn "server context: \{show e}"
  Right expired <- newServerContext (serverConfig (server certs "expired"))
    | Left e => putStrLn "server context: \{show e}"
  Right other <- newServerContext (serverConfig (server certs "other"))
    | Left e => putStrLn "server context: \{show e}"
  Right client <- newClientContext trusting
    | Left e => putStrLn "client context: \{show e}"
  Right systemOnly <- newClientContext defaultClientConfig
    | Left e => putStrLn "client context: \{show e}"

  putStrLn "--- verification"
  scenario "a trusted server" good client "localhost" ok ok
  scenario "by IP address" good client "127.0.0.1" ok sniOf
  scenario "an unknown authority" rogue client "localhost" ok ok
  scenario "only the trust of the system" good systemOnly "localhost" ok ok
  scenario "another name" other client "localhost" ok ok
  scenario "expired" expired client "localhost" ok ok

  putStrLn "--- turning verification off"
  Right insecure <- newClientContext (insecureNoVerification trusting)
    | Left e => putStrLn "client context: \{show e}"
  scenario "no verification, unknown authority" rogue insecure "localhost" ok ok
  scenario "no verification, expired" expired insecure "localhost" ok ok
  Right anyName <- newClientContext ({ verifyHostname := False } trusting)
    | Left e => putStrLn "client context: \{show e}"
  scenario "no name check, another name" other anyName "localhost" ok ok
  scenario "no name check, unknown authority" rogue anyName "localhost" ok ok

  putStrLn "--- ALPN"
  Right alpnServer <- newServerContext ({ alpn := ["http/1.1", "h2"] } (serverConfig (server certs "server")))
    | Left e => putStrLn "server context: \{show e}"
  Right strictServer <- newServerContext ({ alpn := ["http/1.1"], alpnRequired := True } (serverConfig (server certs "server")))
    | Left e => putStrLn "server context: \{show e}"
  Right both <- newClientContext ({ alpn := ["h2", "http/1.1"] } trusting)
    | Left e => putStrLn "client context: \{show e}"
  Right h2only <- newClientContext ({ alpn := ["h2"] } trusting)
    | Left e => putStrLn "client context: \{show e}"
  scenario "the server's preference" alpnServer both "localhost" alpnOf alpnOf
  scenario "the only common one" alpnServer h2only "localhost" alpnOf alpnOf
  scenario "no common protocol" strictServer h2only "localhost" alpnOf alpnOf
  scenario "the client offers none" strictServer client "localhost" alpnOf alpnOf
  scenario "the server takes none" good both "localhost" alpnOf alpnOf
  Left e <- newClientContext ({ alpn := ["a,b"] } trusting)
    | Right _ => putStrLn "a bad ALPN name was taken"
  putStrLn "a bad ALPN name: \{show e}"

  putStrLn "--- SNI"
  Right sni <- newServerContext ({ sniCredentials := [("*.other.example", server certs "other")] }
                                    (serverConfig (server certs "server")))
    | Left e => putStrLn "server context: \{show e}"
  scenario "the default certificate" sni client "localhost" peerOf sniOf
  scenario "a wildcard" sni client "www.other.example" peerOf sniOf
  scenario "no match" sni anyName "other.example" peerOf sniOf

  putStrLn "--- client certificates"
  let withClientCert = { certificate := Just (server certs "client") } trusting
  Right certClient <- newClientContext withClientCert
    | Left e => putStrLn "client context: \{show e}"
  Right required <- newServerContext ({ clientAuth := RequiredClientCertificate, clientTrust := [ca] }
                                         (serverConfig (server certs "server")))
    | Left e => putStrLn "server context: \{show e}"
  Right optional <- newServerContext ({ clientAuth := OptionalClientCertificate, clientTrust := [ca] }
                                         (serverConfig (server certs "server")))
    | Left e => putStrLn "server context: \{show e}"
  scenario "required, sent" required certClient "localhost" readOne (\s => do p <- peerOf s; _ <- sayHi s; pure p)
  scenario "required, not sent" required client "localhost" readOne (\s => do p <- peerOf s; _ <- sayHi s; pure p)
  scenario "optional, sent" optional certClient "localhost" readOne (\s => do p <- peerOf s; _ <- sayHi s; pure p)
  scenario "optional, not sent" optional client "localhost" readOne (\s => do p <- peerOf s; _ <- sayHi s; pure p)
  Right sniRequired <- newServerContext ({ clientAuth := RequiredClientCertificate, clientTrust := [ca],
                                           sniCredentials := [("*.other.example", server certs "other")] }
                                           (serverConfig (server certs "server")))
    | Left e => putStrLn "server context: \{show e}"
  scenario "required, by a certificate of SNI" sniRequired certClient "www.other.example" readOne (\s => do p <- peerOf s; _ <- sayHi s; pure p)
  scenario "required, by a certificate of SNI, not sent" sniRequired client "www.other.example" readOne (\s => do p <- peerOf s; _ <- sayHi s; pure p)

  putStrLn "--- the end of the stream"
  scenario "close_notify" good client "localhost" readTwice (sayBye False)
  scenario "no close_notify" good client "localhost" readTwice (sayBye True)

  putStrLn "--- deadlines"
  Right l <- listenOn (Inet "127.0.0.1" 0) 8
    | Left e => putStrLn "listen: \{show e}"
  Right addr <- localAddress l
    | Left e => putStrLn "localAddress: \{show e}"
  Right sock <- Network.Socket.Async.connect addr Nothing
    | Left e => putStrLn "connect: \{show e}"
  t0 <- now
  r <- Network.TLS.connect client "localhost" sock (Just (t0 + 300000000))
  t1 <- now
  putStrLn "a client against a silent server: \{either show (const "connected") r}, after 0.3 s: \{show (t1 - t0 >= 300000000 && t1 - t0 < seconds 3)}"
  Right peer <- Network.Socket.Async.accept l Nothing
    | Left e => putStrLn "accept: \{show e}"
  ignore (Network.Socket.Async.close peer)
  Right silent <- Network.Socket.Async.connect addr Nothing
    | Left e => putStrLn "connect: \{show e}"
  Right sock <- Network.Socket.Async.accept l Nothing
    | Left e => putStrLn "accept: \{show e}"
  t0 <- now
  r <- Network.TLS.accept good sock (Just (t0 + 300000000))
  t1 <- now
  putStrLn "a server against a silent client: \{either show (const "connected") r}, after 0.3 s: \{show (t1 - t0 >= 300000000 && t1 - t0 < seconds 3)}"
  ignore (Network.Socket.Async.close silent)

  putStrLn "--- configurations"
  Right sock <- Network.Socket.Async.connect addr Nothing
    | Left e => putStrLn "connect: \{show e}"
  r <- Network.TLS.connect client "" sock Nothing
  putStrLn "no host name: \{either show (const "connected") r}"
  ignore (Network.Socket.Async.close l)

  Right pemCert <- readFile (certs ++ "/chain.pem")
    | Left e => putStrLn "read: \{show e}"
  Right pemKey <- readFile (certs ++ "/server.key")
    | Left e => putStrLn "read: \{show e}"
  Right pemCA <- readFile (certs ++ "/ca.pem")
    | Left e => putStrLn "read: \{show e}"
  Right fromText <- newServerContext (serverConfig (MkCredentials (PEMText pemCert) (PEMText pemKey)))
    | Left e => putStrLn "server context: \{show e}"
  Right textTrust <- newClientContext ({ trust := [CAText pemCA] } defaultClientConfig)
    | Left e => putStrLn "client context: \{show e}"
  scenario "PEM text" fromText textTrust "localhost" ok ok
  Right tls13 <- newClientContext ({ minVersion := TLS13 } trusting)
    | Left e => putStrLn "client context: \{show e}"
  scenario "TLS 1.3 at least" good tls13 "localhost" ok ok
  bad (serverConfig (server certs "missing"))
  bad (serverConfig (credentialFiles (certs ++ "/server.pem") (certs ++ "/rsa.key")))
  bad (serverConfig (MkCredentials (PEMText "not a certificate") (PEMText pemKey)))
  bad (serverConfig (MkCredentials (PEMFile (certs ++ "/server.pem")) (PEMText pemKey)))
  r <- newClientContext ({ trust := [CAFile (certs ++ "/missing.pem")] } defaultClientConfig)
  putStrLn (either show (const "made") r)
