-- A server for curl over HTTP/2 (h2c with prior knowledge): it writes its
-- port to the file `port` and serves until it gets `/quit` (or for 60
-- seconds).
import Data.ByteString
import Data.IORef
import Network.HTTP.Router
import System
import System.File

%default covering

routes : Server -> List Route
routes srv =
  [ route GET "/hello" $ \req, _ => pure (textResponse statusOK "hello from idris over HTTP/\{show req.version.major}\n")
  , route GET "/big" $ \_, _ => pure (respond statusOK emptyHeaders (StreamBody Nothing (\w =>
      traverse_ (\i => ignore (writeBody w (Data.ByteString.replicate 100000 (cast (65 + i `mod` 26))))) [the Int 0 .. 49])))
  , route GET "/second" $ \_, _ => pure (textResponse statusOK "second\n")
  , route POST "/echo" $ \req, _ => do
      Right b <- requestBody req
        | Left e => pure (textResponse statusBadRequest (show e ++ "\n"))
      pure (textResponse statusOK ("got \{show (length b)} bytes: \{toStringLossy (Data.ByteString.take 40 b)}\n"))
  , route GET "/quit" $ \_, _ => do
      _ <- fork (stopServer srv 1000)
      pure (textResponse statusOK "bye\n")
  ]

main : IO ()
main = do
  -- the handler needs the server, which exists only once it is started
  ref <- newIORef Nothing
  Right srv <- startServer (defaultServerConfig (Inet "127.0.0.1" 0)) (\req => do
                 Just s <- readIORef ref
                   | Nothing => pure (statusResponse statusServiceUnavailable)
                 router (routes s) req)
    | Left e => putStrLn (show e)
  writeIORef ref (Just srv)
  Right () <- writeFile "port" (show (addrPort (serverAddress srv)))
    | Left e => putStrLn (show e)
  _ <- fork (do sleep 60; stopServer srv 1000)
  waitServer srv
