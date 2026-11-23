||| The computations of the WebSocket opening handshake (RFC 6455 section
||| 4): the `Sec-WebSocket-Accept` value of a key, and the check of a
||| client's `Sec-WebSocket-Key`.  The HTTP part (the `Upgrade` request and
||| the 101 response) is built with the HTTP/1.1 modules.
module Network.WebSocket.Handshake

import Data.ByteString
import Network.HTTP.Base64
import Network.HTTP.SHA1

%default total

||| The GUID that RFC 6455 section 1.3 appends to the key.
export
websocketGUID : ByteString
websocketGUID = fromString "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

||| The value of `Sec-WebSocket-Accept` for a `Sec-WebSocket-Key`: the
||| Base64 of the SHA-1 of the key followed by the GUID.  The key is used as
||| it is (the header value without surrounding whitespace).
|||
||| `acceptKey "dGhlIHNhbXBsZSBub25jZQ=="` is `"s3pPLMBiTxaQ9kYGzzhZRbK+xOo="`.
export
acceptKey : ByteString -> ByteString
acceptKey key = encode (sha1 (key <+> websocketGUID))

||| Is this a valid `Sec-WebSocket-Key`: the Base64 (standard alphabet,
||| padded) of 16 bytes (section 4.1)?
export
validClientKey : ByteString -> Bool
validClientKey key =
  case decode key of
    Just raw => length raw == 16
    Nothing => False

||| A client key from 16 random bytes (which the caller supplies: this
||| library does no I/O).  `Nothing` unless there are exactly 16.
export
clientKey : ByteString -> Maybe ByteString
clientKey nonce = if length nonce == 16 then Just (encode nonce) else Nothing
