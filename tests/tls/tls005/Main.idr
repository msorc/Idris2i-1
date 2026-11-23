-- Interoperation with other implementations: the client of this library
-- against `openssl s_server -www`, and its server against `openssl
-- s_client` and curl (see run).
import Data.Buffer
import Data.List
import Data.Maybe
import Data.String
import Network.Socket.Async
import Network.TLS
import System
import System.File

covering
readAll : TLSSocket -> Buffer -> Int -> IO (Either TLSError Int)
readAll s buf at = do
  r <- recvCode s buf at (4096 - at) (-1)
  if r == 0 then pure (Right at)
    else if r < 0 then Left <$> codeError s r
    else readAll s buf (at + r)

-- Ask an HTTP server for / and show the status line.
covering
client : String -> Int -> IO ()
client certs port = do
  Right ctx <- newClientContext ({ trust := [CAFile (certs ++ "/ca.pem")], alpn := ["http/1.1"] } defaultClientConfig)
    | Left e => putStrLn "client context: \{show e}"
  Right s <- Network.TLS.connectHost ctx "localhost" port Nothing
    | Left e => putStrLn "connect: \{show e}"
  putStrLn "client: \{!(tlsVersion s)}, ALPN \{show !(alpnSelected s)}"
  Just buf <- newBuffer 4096
    | Nothing => putStrLn "newBuffer"
  let req = "GET / HTTP/1.0\r\n\r\n"
  setString buf 0 req
  Right () <- sendAll s buf 0 (cast (length req)) Nothing
    | Left e => putStrLn "send: \{show e}"
  r <- readAll s buf 0
  case r of
    -- (s_server -www closes without close_notify)
    Left UnexpectedEOF => pure ()
    Left e => putStrLn "recv: \{show e}"
    Right _ => pure ()
  txt <- getString buf 0 32
  putStrLn "client: \{fromMaybe "" (head' (lines txt))}"
  ignore (close s)

-- Serve `n` HTTP requests with "hello", saying what each client asked for.
covering
server : String -> String -> Nat -> IO ()
server certs portFile n = do
  Right ctx <- newServerContext ({ alpn := ["h2", "http/1.1"] }
                                   (serverConfig (credentialFiles (certs ++ "/server.pem") (certs ++ "/server.key"))))
    | Left e => putStrLn "server context: \{show e}"
  Right l <- listenOn (Inet "127.0.0.1" 0) 8
    | Left e => putStrLn "listen: \{show e}"
  Right (Inet _ port) <- localAddress l
    | _ => putStrLn "localAddress"
  Right () <- writeFile portFile (show port)
    | Left e => putStrLn "write: \{show e}"
  serve ctx l n
  ignore (Network.Socket.Async.close l)
  where
    serve : ServerContext -> AsyncSocket -> Nat -> IO ()
    serve ctx l Z = pure ()
    serve ctx l (S k) = do
      Right sock <- Network.Socket.Async.accept l Nothing
        | Left e => putStrLn "accept: \{show e}"
      d <- deadlineIn 10000000000
      Right s <- Network.TLS.accept ctx sock (Just d)
        | Left e => do putStrLn "server: \{show e}"; serve ctx l k
      Just buf <- newBuffer 4096
        | Nothing => putStrLn "newBuffer"
      r <- recvCode s buf 0 4096 d
      req <- if r > 0 then getString buf 0 r else pure ""
      putStrLn "server: \{!(tlsVersion s)}, ALPN \{show !(alpnSelected s)}, SNI \{show !(serverName s)}, \{fromMaybe "" (head' (lines req))}"
      let resp = "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nhello\n"
      setString buf 0 resp
      ignore (sendAllCode s buf 0 (cast (length resp)) d)
      ignore (close s)
      serve ctx l k

covering
main : IO ()
main = do
  args <- getArgs
  case drop 1 args of
    ["client", certs, port] => client certs (cast port)
    ["server", certs, portFile, n] => server certs portFile (cast n)
    _ => putStrLn "usage: main client <certs> <port> | server <certs> <port file> <n>"
