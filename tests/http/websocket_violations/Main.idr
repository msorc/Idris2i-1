-- Frames that break RFC 6455, sent by hand to the server of the http
-- library (and by a hand-made server to its client): each one closes the
-- connection with the status code of the RFC.  Also: fragmented messages
-- with pings between the fragments, the closing handshake of a raw peer,
-- and the handshake checks of the server.
import Data.Bits
import Data.Buffer
import Data.ByteString
import Data.ByteString.Internal
import Data.IORef
import Data.List
import Data.String
import HttpTest
import Network.HTTP.Router
import Network.WebSocket
import Network.WebSocket.Frame
import Network.WebSocket.Handshake
import System
import System.Concurrency
import WsTest

%default covering

echo : WebSocket -> IO CloseInfo
echo ws = do
  Right m <- receive ws
    | Left i => pure i
  ignore (sendMessage ws m)
  echo ws

limits : WSConfig
limits = { maxMessageSize := 100000, closeTimeout := 2000 } defaultWSConfig

-- A server that sends the given bytes after its `101` and then prints the
-- frames that the client sends back.
rawServer : Channel String -> ByteString -> Handler
rawServer ev bytes req =
  case checkHandshake defaultAcceptOptions req of
    Left r => pure r
    Right h => pure (respond statusSwitchingProtocols
                       (headersFromPairs [("Upgrade", "websocket"), ("Connection", "Upgrade"),
                                          ("Sec-WebSocket-Accept", acceptKey h.key)])
                       (UpgradeBody (\c => do
                          ignore (sendBytes c bytes (-1))
                          d <- deadlineAfterMs 3000
                          r <- readSome c d
                          case r of
                            Right bs => channelPut ev ("raw server got: " ++ describe bs)
                            Left e => channelPut ev ("raw server: " ++ show e))))
  where
    -- the first frame from the client (masked): its opcode and close code
    describe : ByteString -> String
    describe bs =
      if lengthInt bs < 8 then "\{show (lengthInt bs)} bytes" else
        let op = prim__and_Bits8 (unsafeIndex bs 0) 0x0F
            key = the Bits32 (cast (((cast {to = Int} (unsafeIndex bs 2) * 256 + cast (unsafeIndex bs 3)) * 256
                                     + cast (unsafeIndex bs 4)) * 256 + cast (unsafeIndex bs 5)))
            p = mask key 0 (unsafeSlice 6 (lengthInt bs - 6) bs)
        in "opcode \{show op} code \{show (cast {to = Int} (unsafeIndex p 0) * 256 + cast (unsafeIndex p 1))}"

handler : Channel String -> Handler
handler ev req =
  if req.path == "/echo"
     then pure (acceptWebSocket ({ config := limits } defaultAcceptOptions) req (\ws => do
                  i <- echo ws
                  channelPut ev ("  server: " ++ show i)))
  else if req.path == "/masked" then rawServer ev (frameBytes 0x81 True "hi") req
  else if req.path == "/rsv" then rawServer ev (frameBytes 0xC1 False "hi") req
  else if req.path == "/opcode" then rawServer ev (frameBytes 0x83 False "hi") req
  else if req.path == "/badtext" then rawServer ev (frameBytes 0x81 False (pack [0xED, 0xA0, 0x80])) req
  else if req.path == "/proto" then
    pure (acceptWebSocket ({ subprotocols := ["b", "a"] } defaultAcceptOptions) req abort)
  else if req.path == "/origin" then
    pure (acceptWebSocket ({ checkOrigin := (== Just "https://good.example") } defaultAcceptOptions) req abort)
  else pure (statusResponse statusNotFound)

-- Open a connection, send frames, print what comes back and how the
-- server ended the connection.
violation : SockAddr -> Channel String -> String -> List ByteString -> IO ()
violation addr ev label frames = do
  r <- rawOpen addr "/echo"
  traverse_ (rawSend r) frames
  putStrLn label
  printUntilEnd r 3000
  rawClose r
  putStrLn !(channelGet ev)

m : Bits8 -> ByteString -> ByteString
m b0 p = frameBytes b0 True p

-- A frame with a length field that the payload does not have (the header
-- of a large frame, without its payload).
bigHeader : Bits8 -> Int -> ByteString
bigHeader b0 n = pack ([b0, 0xFF] ++ map (\i => cast (prim__shr_Int n (8 * (7 - i)))) [0 .. 7] ++ [1, 2, 3, 4])

clientCase : String -> String -> Channel String -> IO ()
clientCase base path ev = do
  Right ws <- connectWebSocket defaultConnectOptions (base ++ path)
    | Left e => putStrLn "connect: \{show e}"
  r <- receive ws
  putStrLn "client \{path}: \{either show show r}"
  putStrLn !(channelGet ev)

main : IO ()
main = do
  ev <- makeUnboundedChannel
  Right srv <- startServer (defaultServerConfig (Inet "127.0.0.1" 0)) (handler ev)
    | Left e => putStrLn (show e)
  let addr = serverAddress srv

  violation addr ev "fragments with pings between them" $
    [m 0x01 "Hel", m 0x89 "p1", m 0x00 "lo, ", m 0x89 "p2", m 0x8A "unasked pong", m 0x80 "world", m 0x88 (closeBytes 1000 "bye")]
  violation addr ev "binary fragments of zero bytes" $
    [m 0x02 "", m 0x00 "", m 0x80 "", m 0x88 (closeBytes 1000 "")]
  violation addr ev "close without a code" [m 0x88 ""]
  violation addr ev "close with a private code" [m 0x88 (closeBytes 4321 "private")]
  violation addr ev "unmasked client frame" [frameBytes 0x81 False "hello"]
  violation addr ev "RSV1 set (no extension was agreed)" [m 0xC1 "hello"]
  violation addr ev "RSV2 set" [m 0xA1 "hello"]
  violation addr ev "RSV3 set" [m 0x91 "hello"]
  violation addr ev "reserved opcode 3" [m 0x83 "hello"]
  violation addr ev "reserved opcode 11" [m 0x8B "hello"]
  violation addr ev "fragmented ping" [m 0x09 "hello"]
  violation addr ev "ping of 126 bytes" [m 0x89 (fromString (pack (replicate 126 'p')))]
  violation addr ev "continuation without a message" [m 0x80 "hello"]
  violation addr ev "text inside a fragmented message" [m 0x01 "he", m 0x81 "llo"]
  violation addr ev "invalid UTF-8 in one frame" [m 0x81 (pack [0x61, 0xC3, 0x28])]
  violation addr ev "invalid UTF-8 split across fragments" [m 0x01 (pack [0x61, 0xE2, 0x82]), m 0x80 (pack [0x28, 0x61])]
  violation addr ev "text ending inside a code point" [m 0x01 (pack [0x61, 0xE2]), m 0x80 (pack [0x82])]
  violation addr ev "a surrogate (U+D800)" [m 0x81 (pack [0xED, 0xA0, 0x80])]
  violation addr ev "close payload of one byte" [m 0x88 (pack [3])]
  violation addr ev "close code 1005" [m 0x88 (closeBytes 1005 "")]
  violation addr ev "close code 999" [m 0x88 (closeBytes 999 "")]
  violation addr ev "close code 1004" [m 0x88 (closeBytes 1004 "")]
  violation addr ev "close code 5000" [m 0x88 (closeBytes 5000 "")]
  violation addr ev "close reason not UTF-8" [m 0x88 (closeBytes 1000 "" <+> pack [0xFF])]
  violation addr ev "one frame over the message limit (100000)" [bigHeader 0x82 100001]
  violation addr ev "fragments over the message limit" [m 0x02 (fromString (pack (replicate 60000 'a'))), m 0x80 (fromString (pack (replicate 60000 'b')))]
  violation addr ev "a 64-bit length with the top bit set" [pack [0x82, 0xFF, 0x80, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4]]
  violation addr ev "a length in 16 bits that fits 7" [pack [0x82, 0xFE, 0, 5, 1, 2, 3, 4, 1, 2, 3, 4, 5]]
  violation addr ev "data after the close" [m 0x88 (closeBytes 1000 ""), m 0x81 "late"]

  -- the client against frames that a server may not send
  let base = "ws://\{show addr}"
  clientCase base "/masked" ev
  clientCase base "/rsv" ev
  clientCase base "/opcode" ev
  clientCase base "/badtext" ev

  -- the checks of the handshake
  let ex = \label, req => exchange addr label req True 2000
  ex "valid" (handshakeRequest "/proto" ["Sec-WebSocket-Protocol: a, b", "Sec-WebSocket-Extensions: permessage-deflate"])
  ex "subprotocols in two fields" (handshakeRequest "/proto" ["Sec-WebSocket-Protocol: c", "Sec-WebSocket-Protocol: a"])
  ex "no subprotocol in common" (handshakeRequest "/proto" ["Sec-WebSocket-Protocol: c"])
  ex "version 8" "GET /echo HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 8\r\n\r\n"
  ex "no version" "GET /echo HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
  ex "bad key" "GET /echo HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: c2hvcnQ=\r\nSec-WebSocket-Version: 13\r\n\r\n"
  ex "no key" "GET /echo HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\n\r\n"
  ex "no Upgrade" "GET /echo HTTP/1.1\r\nHost: x\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
  ex "no Connection: Upgrade" "GET /echo HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: keep-alive\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
  ex "tokens in other case and lists" "GET /proto HTTP/1.1\r\nHost: x\r\nUpgrade: WebSocket\r\nConnection: keep-alive, UPGRADE\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
  ex "POST" "POST /echo HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nContent-Length: 0\r\n\r\n"
  ex "HTTP/1.0" "GET /echo HTTP/1.0\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
  ex "origin allowed" (handshakeRequest "/origin" ["Origin: https://good.example"])
  ex "origin refused" (handshakeRequest "/origin" ["Origin: https://evil.example"])
  stopServer srv 1000
