-- Helpers of the tests of the HTTP server and client: raw exchanges over a
-- socket, and responses printed without their `Date` field.
module HttpTest

import Data.Buffer
import Data.ByteString
import Data.List
import Data.String
import Network.HTTP.Transport
import Network.Socket.Async
import System

%default covering

export
orDie : Show e => String -> IO (Either e a) -> IO a
orDie what act = do
  Right x <- act
    | Left e => do putStrLn "\{what}: \{show e}"; exitFailure
  pure x

export
newBuf : Int -> IO Buffer
newBuf n = do
  Just b <- newBuffer n
    | Nothing => do putStrLn "newBuffer"; exitFailure
  pure b

||| Send all of a byte string on a socket.
export
sendRaw : AsyncSocket -> ByteString -> IO ()
sendRaw s bs = do
  let n = cast (length bs)
  b <- newBuf (max 1 n)
  traverse_ (\(i, w) => setBits8 b i w) (zip [0 .. n - 1] (unpack bs))
  ignore (sendAll s b 0 n Nothing)

||| What comes on a socket until the end of the stream or the deadline (ms
||| from now), and whether the stream ended.
export
readUntilEnd : AsyncSocket -> (ms : Int) -> IO (ByteString, Bool)
readUntilEnd s ms = do
  d <- deadlineIn (ms * 1000000)
  b <- newBuf 65536
  go d b []
  where
    go : Int -> Buffer -> List ByteString -> IO (ByteString, Bool)
    go d b acc = do
      r <- recv s b 0 65536 (Just d)
      case r of
        Right 0 => pure (concat (reverse acc), True)
        Right n => do
          bs <- bufferBytes b n
          go d b (bs :: acc)
        Left _ => pure (concat (reverse acc), False)
      where
        bufferBytes : Buffer -> Int -> IO ByteString
        bufferBytes buf n = do
          ws <- traverse (getBits8 buf) [0 .. n - 1]
          pure (pack ws)

||| Read at least until a byte string has been seen (or the deadline).
export
readUntil : AsyncSocket -> String -> (ms : Int) -> IO ByteString
readUntil s pat ms = do
  d <- deadlineIn (ms * 1000000)
  b <- newBuf 4096
  go d b Data.ByteString.empty
  where
    go : Int -> Buffer -> ByteString -> IO ByteString
    go d b acc =
      if isInfixOf (Data.ByteString.fromString pat) acc then pure acc else do
        r <- recv s b 0 4096 (Just d)
        case r of
          Right 0 => pure acc
          Right n => do
            ws <- traverse (getBits8 b) [0 .. n - 1]
            go d b (acc <+> pack ws)
          Left _ => pure acc

||| A response (or several) as lines, without the `Date` fields and the CRs.
export
showResponse : ByteString -> String
showResponse bs =
  let ls = lines (toStringLossy bs)
      ls' = filter (not . Data.String.isPrefixOf "Date: ") (map (\l => if Data.String.isSuffixOf "\r" l then substr 0 (minus (length l) 1) l else l) ls)
  in unlines ls'

||| Print an exchange: send the bytes, shut down the writing side if asked,
||| read until the end (for at most `ms`) and print what came, and whether
||| the server closed the connection.
export
exchange : SockAddr -> (label : String) -> String -> (shutWrite : Bool) -> (ms : Int) -> IO ()
exchange addr label req shut ms = do
  s <- orDie "connect" (connect addr Nothing)
  sendRaw s (fromString req)
  when shut $ ignore (shutdown s ShutWrite)
  (resp, ended) <- readUntilEnd s ms
  ignore (close s)
  putStrLn "--- \{label}"
  putStr (showResponse resp)
  putStrLn (if ended then "[closed by the server]" else "[still open]")
