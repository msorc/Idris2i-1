-- A closed-loop HTTP/2 load generator over h2c (prior knowledge), with
-- the client of the library: `conns` clients (one connection each), each
-- with `streams` threads that send a request, read the whole response and
-- send the next one, for a number of seconds.  It prints the same line
-- as the Go load generator.
--
--   h2load PORT CONNS STREAMS SECONDS PATH [BODYFILE]
import Data.ByteString
import Data.IORef
import Data.List
import Network.HTTP.Client
import System
import System.Clock
import System.Concurrency
import System.File

%default covering

nowMs : IO Integer
nowMs = do
  t <- clockTime Monotonic
  pure (toNano t `div` 1000000)

loop : Client -> String -> Maybe ByteString -> Integer -> Int -> IO Int
loop c url body end n = do
  t <- nowMs
  if t >= end then pure n else do
    r <- the (IO (Either HttpError Reply)) $ case body of
           Nothing => fetch c GET url emptyHeaders NoRequestBody
           Just b => fetch c POST url (addHeader "Content-Type" "application/json" emptyHeaders) (RequestBytes b)
    case r of
      Right rep => if rep.status.code < 300 then loop c url body end (n + 1) else pure (-1)
      Left _ => pure (-1)

main : IO ()
main = do
  (_ :: port :: conns :: streams :: secs :: path :: rest) <- getArgs
    | _ => putStrLn "usage: h2load PORT CONNS STREAMS SECONDS PATH [BODYFILE]"
  body <- case rest of
            (f :: _) => do Right s <- readFile f
                             | Left e => do putStrLn (show e); exitFailure
                           pure (Just (fromString s))
            [] => pure Nothing
  let url = "http://127.0.0.1:" ++ port ++ path
  let nc = the Int (cast conns)
  let ns = the Int (cast streams)
  t0 <- nowMs
  let end = t0 + cast (the Int (cast secs)) * 1000
  done <- makeChannel
  for_ [1 .. nc] $ \_ => do
    c <- newClient ({ http2PriorKnowledge := True, requestTimeout := 30000 } defaultClientConfig)
    for_ [1 .. ns] $ \_ => fork (do n <- loop c url body end 0; channelPut done n)
  rs <- traverse (\_ => channelGet done) [1 .. nc * ns]
  t1 <- nowMs
  let n = sum (map (max 0) rs)
  let failed = length (filter (< 0) rs)
  let secsF = cast {to = Double} (t1 - t0) / 1000
  putStrLn "requests \{show n} seconds \{show secsF} rps \{show (cast {to = Double} n / secsF)} failed_conns \{show failed}"
