-- The server and the client on the Chez back end, whose threads are OS
-- threads: reads and writes block their thread instead of parking it.  A
-- few clients at a time, a persistent connection each, then a shutdown.
import Data.ByteString
import Data.List
import Network.HTTP.Client
import Network.HTTP.Router
import System
import System.Concurrency

%default covering

routes : List Route
routes =
  [ route GET "/hello/:name" $ \_, ps =>
      pure (textResponse statusOK ("hello " ++ maybe "?" id (param "name" ps)))
  , route POST "/echo" $ \req, _ => do
      Right b <- requestBody req
        | Left e => pure (statusResponse statusBadRequest)
      pure (bytesResponse statusOK "text/plain" b)
  ]

bodyIs : String -> Either HttpError Reply -> Bool
bodyIs s (Right r) = toStringLossy r.body == s
bodyIs _ (Left _) = False

worker : String -> Channel (Bool, Int) -> Int -> IO ()
worker base ch i = do
  c <- newClient defaultClientConfig
  rs <- traverse (\j => httpGet c (base ++ "/hello/" ++ show i ++ "-" ++ show j)) [1 .. 10]
  e <- httpPost c (base ++ "/echo") "text/plain" (fromString (show i))
  let ok = all (\(j, r) => bodyIs ("hello " ++ show i ++ "-" ++ show j) r) (zip [1 .. 10] rs)
           && bodyIs (show i) e
  n <- connectionsOpened c
  closeIdle c
  channelPut ch (ok, n)

main : IO ()
main = do
  Right srv <- startServer (defaultServerConfig (Inet "127.0.0.1" 0)) (router routes)
    | Left e => putStrLn (show e)
  let base = "http://\{show (serverAddress srv)}"
  ch <- makeChannel
  traverse_ (\i => fork (worker base ch i)) [1 .. 4]
  rs <- traverse (\_ => channelGet ch) [1 .. 4]
  putStrLn "4 clients, 11 requests each: all right: \{show (all fst rs)}, one connection each: \{show (all ((== 1) . snd) rs)}"
  n <- acceptedConnections srv
  putStrLn "accepted: \{show n}"
  stopServer srv 1000
  r <- connect (serverAddress srv) Nothing
  putStrLn ("connect after the shutdown: " ++ either (const "refused") (const "accepted") r)
