||| The negative result codes of the TLS operations that are not minus an
||| errno code (`IDRIS_TLS_*` of `c/idris_tls.h`).  They are all at -1000 or
||| below, far from the errno codes of every system, so that a result can
||| be told apart from those of `Network.Socket.Async`.
module Network.TLS.Codes

%default total

||| The operation must wait until the socket is readable, then be called
||| again.  The loops of `Network.TLS` do that: it is never returned by them.
public export
codeWantRead : Int
codeWantRead = -1001

||| The operation must wait until the socket is writable, then be called
||| again (never returned by the loops of `Network.TLS`).
public export
codeWantWrite : Int
codeWantWrite = -1002

||| The peer closed the TLS session cleanly (close_notify).  `recvCode`
||| returns 0 instead; the handshake can return it.
public export
codeClosed : Int
codeClosed = -1003

||| The stream ended without a close_notify: the peer went away, or the end
||| of the data may have been cut off by someone in the middle.
public export
codeUnexpectedEOF : Int
codeUnexpectedEOF = -1004

||| An error of TLS: an alert of the peer, a message that is not valid, no
||| version or cipher in common...  The connection keeps its message.
public export
codeProtocolError : Int
codeProtocolError = -1005

||| The certificate of the peer was rejected (unknown issuer, wrong name,
||| expired, ...).  The connection keeps its message and the X509 result.
public export
codeVerifyError : Int
codeVerifyError = -1006

||| A context or a connection could not be set up.
public export
codeConfigError : Int
codeConfigError = -1007

||| Is it a result code of TLS (rather than minus an errno code)?  They are
||| all at -1000 or below; errno codes are much smaller on every system.
public export
isTLSCode : Int -> Bool
isTLSCode c = c <= -1000
