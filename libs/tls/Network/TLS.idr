||| TLS client and server connections over the non-blocking sockets of
||| `Network.Socket.Async`, with OpenSSL 3.
|||
||| A program makes a context once (`newClientContext`, `newServerContext`)
||| from a configuration (`defaultClientConfig`, `serverConfig`), then
||| wraps its connected sockets: `connect` (or `connectHost`) runs the
||| handshake of a client on a socket, `accept` the one of a server on a
||| socket that `Network.Socket.Async.accept` gave.  The connection
||| (`TLSSocket`) is then used like an `AsyncSocket`, with the same two
||| layers:
|||
||| * the functions that return `Either TLSError a` (`recv`, `sendAll`,
|||   ...);
||| * the same operations returning a plain `Int` code, in the shapes of
|||   `Network.Socket.Async` (`recvCode`, `sendCode`, `sendAllCode`,
|||   `sendAll2Code`): a count, or a negative code, which is minus an errno
|||   code (`-ETIMEDOUT` at the deadline, `-EBADF` once the connection was
|||   closed, `-ECONNRESET`, ...) as with sockets, or a code of TLS at -1000
|||   or below (`Network.TLS.Codes`, `isTLSCode`): `codeError` and
|||   `codeMessage` tell them all apart.
|||
||| A thread that waits parks in the scheduler on the RefC back end (every
||| operation waits for the socket only after OpenSSL said that it would
||| block, as the edge-triggered reactor needs), and blocks its OS thread in
||| poll(2) on the Scheme back ends.
|||
||| Verification is on by default: a client checks that the certificate of
||| the server is issued by a trusted authority (those of the system by
||| default), is valid now, and is for the name it connects to.  TLS 1.2 is
||| the oldest version accepted.
|||
||| Rules:
|||
||| * After `connect` or `accept`, the socket belongs to the connection:
|||   close it with `close` of this module, which sends close_notify and
|||   then closes the socket.  A connection that is dropped without `close`
|||   has its TLS session freed by the collector, but not its socket.
||| * One thread may read while another writes (an internal lock serialises
|||   the calls to OpenSSL, each of which is short).  Two threads that read,
|||   or two that write, on one connection at the same time are not
|||   supported: their data would interleave in any order.
module Network.TLS

import Data.Buffer
import Data.List
import Data.List1
import Data.String
import public Network.Socket.Async
import public Network.TLS.Codes
import Network.TLS.FFI
import System.IO.Fd

%default total

-- ---------------------------------------------------------------------------
-- Errors

||| What went wrong.
public export
data TLSError
  = ||| The deadline came first (`ETIMEDOUT`).
    Timeout
  | ||| The connection was closed by this program (`EBADF`), maybe by another
    ||| thread while this one waited.
    Closed
  | ||| An error of the system on the socket: its errno code and message.
    SysError Int String
  | ||| A name could not be resolved (`connectHost`).
    ResolveError String
  | ||| The peer closed the TLS session (close_notify) during the handshake.
    PeerClosed
  | ||| The connection ended without a close_notify: the peer went away, or
    ||| the end of the data may have been cut off.
    UnexpectedEOF
  | ||| An error of TLS: an alert of the peer, an invalid message, no common
    ||| version or cipher...: the message of OpenSSL.
    ProtocolError String
  | ||| The certificate of the peer was rejected: the result code of X509
    ||| verification (`X509_V_ERR_*`) and its message.
    VerifyError Int String
  | ||| A context or a connection could not be set up: a certificate that
    ||| cannot be read, a key that does not match, ...
    ConfigError String

export
Show TLSError where
  show Timeout = "timed out"
  show Closed = "connection closed"
  show (SysError e msg) = msg ++ " (errno " ++ show e ++ ")"
  show (ResolveError msg) = "cannot resolve: " ++ msg
  show PeerClosed = "the peer closed the TLS session"
  show UnexpectedEOF = "the connection ended without a TLS close_notify"
  show (ProtocolError msg) = "TLS error: " ++ msg
  show (VerifyError _ msg) = msg
  show (ConfigError msg) = "TLS configuration error: " ++ msg

export
Eq TLSError where
  Timeout == Timeout = True
  Closed == Closed = True
  SysError a _ == SysError b _ = a == b
  ResolveError a == ResolveError b = a == b
  PeerClosed == PeerClosed = True
  UnexpectedEOF == UnexpectedEOF = True
  ProtocolError a == ProtocolError b = a == b
  VerifyError a _ == VerifyError b _ = a == b
  ConfigError a == ConfigError b = a == b
  _ == _ = False

||| The error of the socket layer as an error of this module.
export
fromNetError : NetError -> TLSError
fromNetError Timeout = Timeout
fromNetError Closed = Closed
fromNetError (SysError e msg) = SysError e msg
fromNetError (ResolveError msg) = ResolveError msg

||| The message of a code of TLS that needs no connection (see
||| `codeMessage` for the others), or of minus an errno code.
export
staticCodeMessage : Int -> String
staticCodeMessage c
    = if isTLSCode c then unsafePerformIO (primIO (prim__codeMessage c))
      else errnoMessage (negate c)

-- ---------------------------------------------------------------------------
-- Configuration

||| The oldest version of the protocol to accept.
public export
data TLSVersion = TLS12 | TLS13

versionCode : TLSVersion -> Int
versionCode TLS12 = 12
versionCode TLS13 = 13

||| PEM data: in a file, or as text.
public export
data PEM = PEMFile String | PEMText String

||| A certificate chain (the certificate first, then the intermediate
||| ones) and its private key.
public export
record Credentials where
  constructor MkCredentials
  certificateChain : PEM
  privateKey : PEM

||| Credentials from two PEM files.
export
credentialFiles : (chain, key : String) -> Credentials
credentialFiles chain key = MkCredentials (PEMFile chain) (PEMFile key)

||| Where the trusted certificates come from.
public export
data Trust
  = ||| Those of the system (as OpenSSL finds them; `SSL_CERT_FILE` and
    ||| `SSL_CERT_DIR` override the place).
    SystemTrust
  | ||| A PEM file of certificates.
    CAFile String
  | ||| A directory of certificates hashed with `openssl rehash`.
    CADirectory String
  | ||| PEM text of certificates.
    CAText String

||| The configuration of a client.
public export
record ClientConfig where
  constructor MkClientConfig
  ||| The oldest version to accept (`TLS12` by default).
  minVersion : TLSVersion
  ||| The trusted certificates (`[SystemTrust]` by default).
  trust : List Trust
  ||| Verify the certificate of the server (on by default).  Off, any
  ||| server is accepted, and the connection protects from nothing but
  ||| passive listeners: for tests only (see `insecureNoVerification`).
  verifyPeer : Bool
  ||| Check that the certificate of the server is for the name given to
  ||| `connect` (on by default; only with `verifyPeer`).
  verifyHostname : Bool
  ||| The protocols offered with ALPN, in order ("h2", "http/1.1"); none by
  ||| default.
  alpn : List String
  ||| A client certificate, for the servers that ask for one.
  certificate : Maybe Credentials

||| The configuration of a client that verifies servers with the
||| certificates of the system, accepts TLS 1.2 and 1.3, and offers no ALPN.
export
defaultClientConfig : ClientConfig
defaultClientConfig = MkClientConfig TLS12 [SystemTrust] True True [] Nothing

||| Turn every verification of the server off.  For tests only: such a
||| client talks to anyone that answers.
export
insecureNoVerification : ClientConfig -> ClientConfig
insecureNoVerification = { verifyPeer := False, verifyHostname := False }

||| What a server asks of its clients.
public export
data ClientAuth
  = ||| No client certificate (the default).
    NoClientCertificate
  | ||| A client certificate, verified when the client sends one.
    OptionalClientCertificate
  | ||| A client certificate that the client must send, verified.
    RequiredClientCertificate

||| The configuration of a server.
public export
record ServerConfig where
  constructor MkServerConfig
  ||| The oldest version to accept (`TLS12` by default).
  minVersion : TLSVersion
  ||| The certificate and key of the server.
  credentials : Credentials
  ||| Other certificates, for the names that the clients ask for with SNI:
  ||| a host name, or `*.domain` for the names of one more label (in any
  ||| case of letters).  The first one that matches is used; `credentials`
  ||| when none does.
  sniCredentials : List (String, Credentials)
  ||| The protocols of ALPN that the server takes, by preference: it
  ||| selects the first one that the client offers too.
  alpn : List String
  ||| When the client offers ALPN protocols but none of `alpn`: fail the
  ||| handshake (alert no_application_protocol) rather than go on without
  ||| ALPN (the default).
  alpnRequired : Bool
  ||| Client certificates (none by default).
  clientAuth : ClientAuth
  ||| The certificates that client certificates must be issued by.
  clientTrust : List Trust

||| The configuration of a server with these credentials, TLS 1.2 and 1.3,
||| no ALPN and no client certificates.
export
serverConfig : Credentials -> ServerConfig
serverConfig creds = MkServerConfig TLS12 creds [] [] False NoClientCertificate []

-- ---------------------------------------------------------------------------
-- Contexts

||| A context of clients: a configuration ready for connections.  Freed by
||| the collector, once its connections are gone too.
export
data ClientContext = MkClientContext GCAnyPtr Bool -- (and whether to verify the host name)

||| A context of servers.
export
data ServerContext = MkServerContext GCAnyPtr

-- Run the steps of a configuration, stopping at the first that fails.
ctxSteps : GCAnyPtr -> List (IO Int) -> IO (Either TLSError ())
ctxSteps ctx [] = pure (Right ())
ctxSteps ctx (s :: ss)
    = do r <- s
         if r == 0 then ctxSteps ctx ss
           else do msg <- primIO $ prim__ctxError ctx
                   pure (Left (ConfigError msg))

pemArgs : Credentials -> Either TLSError (String, String, Int)
pemArgs (MkCredentials (PEMFile c) (PEMFile k)) = Right (c, k, 0)
pemArgs (MkCredentials (PEMText c) (PEMText k)) = Right (c, k, 1)
pemArgs _ = Left (ConfigError "a certificate chain and its key must both be files or both be text")

useCredentials : GCAnyPtr -> Credentials -> IO Int
useCredentials ctx creds
    = case pemArgs creds of
        Right (c, k, t) => primIO $ prim__ctxUseCert ctx c k t
        Left _ => pure codeConfigError

trustStep : GCAnyPtr -> Trust -> IO Int
trustStep ctx SystemTrust = primIO $ prim__ctxUseSystemTrust ctx
trustStep ctx (CAFile f) = primIO $ prim__ctxTrust ctx f ""
trustStep ctx (CADirectory d) = primIO $ prim__ctxTrust ctx "" d
trustStep ctx (CAText t) = primIO $ prim__ctxTrustPEM ctx t

-- The names of ALPN as the C side takes them, or an error.
alpnList : List String -> Either TLSError String
alpnList ps
    = if any (\p => p == "" || length p > 255 || isInfixOf "," p) ps
         then Left (ConfigError "an ALPN protocol name must be 1 to 255 bytes, without a comma")
         else Right (joinBy "," ps)

newContext : (isServer : Bool) -> TLSVersion -> IO (Either TLSError GCAnyPtr)
newContext isServer v
    = do p <- primIO $ prim__ctxNew (if isServer then 1 else 0) (versionCode v)
         if prim__nullAnyPtr p /= 0
           then pure (Left (ConfigError "OpenSSL cannot make a context"))
           else Right <$> onCollectAny p (\q => primIO (prim__ctxFree q))

||| A context for clients with this configuration.
export
newClientContext : HasIO io => ClientConfig -> io (Either TLSError ClientContext)
newClientContext cfg = liftIO $ do
    Right ctx <- newContext False cfg.minVersion
      | Left e => pure (Left e)
    Right protos <- pure (alpnList cfg.alpn)
      | Left e => pure (Left e)
    Right _ <- pure (traverse pemArgs cfg.certificate)
      | Left e => pure (Left e)
    Right () <- ctxSteps ctx $
                  [primIO $ prim__ctxSetVerify ctx (if cfg.verifyPeer then 1 else 0)]
                  ++ map (trustStep ctx) cfg.trust
                  ++ (if null cfg.alpn then [] else [primIO $ prim__ctxSetALPN ctx protos 0])
                  ++ maybe [] (\c => [useCredentials ctx c]) cfg.certificate
      | Left e => pure (Left e)
    pure (Right (MkClientContext ctx (cfg.verifyPeer && cfg.verifyHostname)))

||| A context for servers with this configuration.
export
newServerContext : HasIO io => ServerConfig -> io (Either TLSError ServerContext)
newServerContext cfg = liftIO $ do
    Right ctx <- newContext True cfg.minVersion
      | Left e => pure (Left e)
    Right protos <- pure (alpnList cfg.alpn)
      | Left e => pure (Left e)
    Right _ <- pure (traverse (pemArgs . snd) cfg.sniCredentials)
      | Left e => pure (Left e)
    Right _ <- pure (pemArgs cfg.credentials)
      | Left e => pure (Left e)
    Right () <- ctxSteps ctx $
                  [ useCredentials ctx cfg.credentials
                  , primIO $ prim__ctxSetVerify ctx (case cfg.clientAuth of
                                                       NoClientCertificate => 0
                                                       OptionalClientCertificate => 1
                                                       RequiredClientCertificate => 2) ]
                  ++ map (trustStep ctx) cfg.clientTrust
                  ++ map (sniStep ctx) cfg.sniCredentials
                  ++ (if null cfg.alpn then []
                        else [primIO $ prim__ctxSetALPN ctx protos (if cfg.alpnRequired then 1 else 0)])
      | Left e => pure (Left e)
    pure (Right (MkServerContext ctx))
  where
    sniStep : GCAnyPtr -> (String, Credentials) -> IO Int
    sniStep ctx (name, creds)
        = case pemArgs creds of
            Right (c, k, t) => primIO $ prim__ctxAddSNICert ctx name c k t
            Left _ => pure codeConfigError

-- ---------------------------------------------------------------------------
-- Connections

||| A TLS connection over a non-blocking socket.
export
data TLSSocket
  = -- (the socket, the connection, and the context, which is kept alive,
    -- with what the callbacks of OpenSSL use, as long as the connection)
    MkTLSSocket AsyncSocket GCAnyPtr GCAnyPtr

%inline
sockOf : TLSSocket -> AsyncSocket
sockOf (MkTLSSocket s _ _) = s

%inline
connOf : TLSSocket -> GCAnyPtr
connOf (MkTLSSocket _ c _) = c

%inline
fdOf : TLSSocket -> Int
fdOf (MkTLSSocket s _ _) = s.fd

||| The socket of the connection, for its addresses and options.  Do not
||| read, write or close it directly.
export
socketOf : TLSSocket -> AsyncSocket
socketOf = sockOf

export
Show TLSSocket where
  show s = "TLS over " ++ show (sockOf s)

||| The message of a negative code of an operation on the connection:
||| the message that OpenSSL gave for an error of TLS or of verification,
||| the message of the errno code otherwise.
export
codeMessage : HasIO io => TLSSocket -> (code : Int) -> io String
codeMessage s c
    = if c == codeProtocolError || c == codeVerifyError || c == codeConfigError
         then primIO $ prim__connError (connOf s)
         else pure (staticCodeMessage c)

||| The error of a negative code of `recvCode` and the like.
export
codeError : HasIO io => TLSSocket -> (code : Int) -> io TLSError
codeError s c
    = if c == codeClosed then pure PeerClosed
      else if c == codeUnexpectedEOF then pure UnexpectedEOF
      else if c == codeProtocolError then ProtocolError <$> codeMessage s c
      else if c == codeVerifyError
        then do v <- primIO $ prim__verifyResult (connOf s)
                VerifyError v <$> codeMessage s c
      else if c == codeConfigError then ConfigError <$> codeMessage s c
      else if c == negate etimedout then pure Timeout
      else if c == negate ebadf then pure Closed
      else pure (SysError (negate c) (errnoMessage (negate c)))

-- Wait for `fd`: 1 to try again, or the code to give up with.
%inline
waitCode : Int -> Int -> Int -> IO Int
waitCode fd ev deadline
    = do w <- primIO $ prim__wait fd ev (cast deadline)
         pure $ if w == 1 then 1
                else if w == 0 then negate etimedout
                else w

-- Is the range in the buffer?
%inline
checkRange : Buffer -> Int -> Int -> IO Bool
checkRange buf offset len
    = do size <- rawSize buf
         pure (offset >= 0 && len >= 0 && offset <= size - len)

%inline
deadlineCode : Maybe Int -> Int
deadlineCode Nothing = -1
deadlineCode (Just d) = if d < 0 then 0 else d

-- Wait as a code of TLS says and give 1 to call again, or give the code.
%inline
retryCode : Int -> Int -> Int -> IO Int
retryCode fd r deadline
    = if r == codeWantRead then waitCode fd 1 deadline
      else if r == codeWantWrite then waitCode fd 2 deadline
      else pure r

covering
handshakeLoop : GCAnyPtr -> Int -> Int -> IO Int
handshakeLoop c fd deadline
    = do r <- primIO $ prim__handshake c
         if r >= 0 then pure r else do
           w <- retryCode fd r deadline
           if w == 1 then handshakeLoop c fd deadline else pure w

covering
readLoop : GCAnyPtr -> Int -> Buffer -> Int -> Int -> Int -> IO Int
readLoop c fd buf offset len deadline
    = do r <- primIO $ prim__read c buf offset len
         if r >= 0 then pure r
           else if r == codeClosed then pure 0
           else do w <- retryCode fd r deadline
                   if w == 1 then readLoop c fd buf offset len deadline else pure w

covering
writeLoop : GCAnyPtr -> Int -> Buffer -> Int -> Int -> Int -> IO Int
writeLoop c fd buf offset len deadline
    = do r <- primIO $ prim__write c buf offset len
         if r >= 0 then pure r else do
           w <- retryCode fd r deadline
           if w == 1 then writeLoop c fd buf offset len deadline else pure w

covering
writeAllLoop : GCAnyPtr -> Int -> Buffer -> Int -> Int -> Int -> IO Int
writeAllLoop c fd buf offset len deadline
    = if len <= 0 then pure 0 else do
        r <- writeLoop c fd buf offset len deadline
        if r < 0 then pure r else writeAllLoop c fd buf (offset + r) (len - r) deadline

covering
write2Loop : GCAnyPtr -> Int -> Buffer -> Int -> Int -> Buffer -> Int -> Int -> Int -> IO Int
write2Loop c fd b1 o1 l1 b2 o2 l2 deadline
    = if l1 <= 0 then writeAllLoop c fd b2 o2 l2 deadline else do
        r <- primIO $ prim__write2 c b1 o1 l1 b2 o2 l2
        if r < 0
          then do w <- retryCode fd r deadline
                  if w == 1 then write2Loop c fd b1 o1 l1 b2 o2 l2 deadline else pure w
          else if r >= l1
            then writeAllLoop c fd b2 (o2 + (r - l1)) (l2 - (r - l1)) deadline
            else write2Loop c fd b1 (o1 + r) (l1 - r) b2 o2 l2 deadline

covering
shutdownLoop : GCAnyPtr -> Int -> Int -> IO Int
shutdownLoop c fd deadline
    = do r <- primIO $ prim__shutdown c
         if r == 0 then pure 0
           else if r == 1
             then do t <- now
                     if deadline >= 0 && t >= deadline then pure (negate etimedout)
                       else shutdownLoop c fd deadline
           else do w <- retryCode fd r deadline
                   if w == 1 then shutdownLoop c fd deadline else pure w

-- Free the TLS session, and close the socket the first time.
release : TLSSocket -> IO Int
release s
    = do first <- primIO $ prim__connRelease (connOf s)
         if first == 1 then closeFd (fdOf s) else pure 0

||| Close the connection: send close_notify, wait until the deadline for the
||| close_notify of the peer (so that the data that it may still send does
||| not make the system reset the connection before the peer read
||| everything), free the TLS session and close the socket.  0, or minus an
||| errno code of close(2).  Closing a closed connection does nothing.
export covering
closeCodeWithin : HasIO io => TLSSocket -> (deadline : Int) -> io Int
closeCodeWithin s deadline
    = liftIO $ do ignore $ shutdownLoop (connOf s) (fdOf s) deadline
                  release s

||| Close the connection, waiting at most a second for the close_notify of
||| the peer (see `closeCodeWithin`): 0, or minus an errno code.
export covering
closeCode : HasIO io => TLSSocket -> io Int
closeCode s
    = do d <- deadlineIn 1000000000
         closeCodeWithin s d

||| Close the connection, waiting at most a second for the close_notify of
||| the peer (see `closeCodeWithin`).
export covering
close : HasIO io => TLSSocket -> io (Either TLSError ())
close s
    = do r <- closeCode s
         if r < 0 then Left <$> codeError s r else pure (Right ())

covering
closeNotifyLoop : GCAnyPtr -> Int -> Int -> IO Int
closeNotifyLoop c fd deadline
    = do r <- primIO $ prim__shutdown c
         if r == 0 || r == 1 || r == codeWantRead then pure 0 else do
           w <- retryCode fd r deadline
           if w == 1 then closeNotifyLoop c fd deadline else pure w

||| End the writing side of the connection: send close_notify (waiting
||| until the deadline for the socket to take it), without waiting for the
||| close_notify of the peer.  The connection can still be read, until the
||| peer ends its side; `close` (or `closeCodeWithin`) then ends it.  0, or
||| a negative code, as for `recvCode`.  Sending it again does nothing.
export covering
closeNotifyCode : HasIO io => TLSSocket -> (deadline : Int) -> io Int
closeNotifyCode s deadline = liftIO $ closeNotifyLoop (connOf s) (fdOf s) deadline

||| Close the connection at once, without close_notify: the peer sees
||| `UnexpectedEOF`.
export
abort : HasIO io => TLSSocket -> io ()
abort s = ignore $ liftIO $ release s

-- Make a connection of the context on the socket, and run its handshake.
covering
start : GCAnyPtr -> AsyncSocket -> (host : String) -> (verifyHost : Bool) ->
        Int -> IO (Either TLSError TLSSocket)
start ctx sock host verifyHost deadline
    = do p <- primIO $ prim__connNew ctx sock.fd host (if verifyHost then 1 else 0)
         if prim__nullAnyPtr p /= 0
           then do ignore (Network.Socket.Async.close sock)
                   pure (Left (ConfigError "out of memory"))
           else do
             c <- onCollectAny p (\q => primIO (prim__connFree q))
             let s = MkTLSSocket sock c ctx
             st <- primIO $ prim__connStatus c
             r <- if st /= 0 then pure st else handshakeLoop c sock.fd deadline
             if r == 0 then pure (Right s) else do
               e <- codeError s r
               ignore (release s)
               pure (Left e)

||| Run the handshake of a client on a connected socket, until the deadline:
||| the server is verified as the context says, for the name `host` (also
||| sent with SNI unless it is an IP address).  The socket belongs to the
||| connection afterwards; it is closed when the handshake fails.
export covering
connect : HasIO io => ClientContext -> (host : String) -> AsyncSocket ->
          (deadline : Maybe Int) -> io (Either TLSError TLSSocket)
connect (MkClientContext ptr verify) host sock deadline
    = if verify && host == ""
         then do ignore (Network.Socket.Async.close sock)
                 pure (Left (ConfigError "no host name to verify the server for"))
         else liftIO $ start ptr sock host verify (deadlineCode deadline)

||| Resolve a name, connect to it (`Network.Socket.Async.connectHost`) and
||| run the handshake, all before the deadline.
export covering
connectHost : HasIO io => ClientContext -> (host : String) -> (port : Int) ->
              (deadline : Maybe Int) -> io (Either TLSError TLSSocket)
connectHost ctx host port deadline
    = do Right sock <- Network.Socket.Async.connectHost host port deadline
           | Left e => pure (Left (fromNetError e))
         connect ctx host sock deadline

||| Run the handshake of a server on a socket that a listening socket
||| accepted, until the deadline.  The socket belongs to the connection
||| afterwards; it is closed when the handshake fails.
export covering
accept : HasIO io => ServerContext -> AsyncSocket -> (deadline : Maybe Int) ->
         io (Either TLSError TLSSocket)
accept (MkServerContext ptr) sock deadline = liftIO $ start ptr sock "" False (deadlineCode deadline)

-- ---------------------------------------------------------------------------
-- Receiving and sending: codes

||| Receive at most `len` bytes into the buffer from `offset`, waiting until
||| some come or until the deadline (an absolute time on the clock of
||| `now`; negative for none): the number of bytes, 0 at the end of the
||| TLS stream (the peer sent close_notify), or a negative code (see
||| `codeError`): `codeUnexpectedEOF` when the stream ended without
||| close_notify, `-ETIMEDOUT` at the deadline, `-EBADF` when the
||| connection was closed, `-EINVAL` when the range is not in the buffer.
export covering
recvCode : HasIO io => TLSSocket -> Buffer -> (offset, len : Int) ->
           (deadline : Int) -> io Int
recvCode s buf offset len deadline
    = liftIO $ do True <- checkRange buf offset len
                    | False => pure (negate einval)
                  readLoop (connOf s) (fdOf s) buf offset len deadline

||| Send at most `len` bytes of the buffer from `offset`, waiting until some
||| can be sent: the number of bytes sent (maybe fewer than `len`), or a
||| negative code, as for `recvCode`.
export covering
sendCode : HasIO io => TLSSocket -> Buffer -> (offset, len : Int) ->
           (deadline : Int) -> io Int
sendCode s buf offset len deadline
    = liftIO $ do True <- checkRange buf offset len
                    | False => pure (negate einval)
                  writeLoop (connOf s) (fdOf s) buf offset len deadline

||| Send all `len` bytes of the buffer from `offset`: 0, or a negative
||| code, as for `recvCode` (some of the bytes may have been sent then).
export covering
sendAllCode : HasIO io => TLSSocket -> Buffer -> (offset, len : Int) ->
              (deadline : Int) -> io Int
sendAllCode s buf offset len deadline
    = liftIO $ do True <- checkRange buf offset len
                    | False => pure (negate einval)
                  writeAllLoop (connOf s) (fdOf s) buf offset len deadline

||| Send all of two ranges, one after the other (a head and a body, say),
||| in one TLS record when they fit in one: 0, or a negative code, as for
||| `recvCode`.
export covering
sendAll2Code : HasIO io => TLSSocket ->
               Buffer -> (offset1, len1 : Int) ->
               Buffer -> (offset2, len2 : Int) ->
               (deadline : Int) -> io Int
sendAll2Code s b1 o1 l1 b2 o2 l2 deadline
    = liftIO $ do True <- checkRange b1 o1 l1
                    | False => pure (negate einval)
                  True <- checkRange b2 o2 l2
                    | False => pure (negate einval)
                  write2Loop (connOf s) (fdOf s) b1 o1 l1 b2 o2 l2 deadline

covering
readExactlyLoop : GCAnyPtr -> Int -> Buffer -> Int -> Int -> Int -> Int -> IO Int
readExactlyLoop c fd buf offset len deadline done
    = if len <= 0 then pure done else do
        r <- readLoop c fd buf offset len deadline
        if r < 0 then pure r
          else if r == 0 then pure done
          else readExactlyLoop c fd buf (offset + r) (len - r) deadline (done + r)

||| Receive `len` bytes into the buffer from `offset`, unless the TLS stream
||| ends first: the number of bytes received (`len`, or fewer at the end of
||| the stream), or a negative code, as for `recvCode`.
export covering
recvExactlyCode : HasIO io => TLSSocket -> Buffer -> (offset, len : Int) ->
                  (deadline : Int) -> io Int
recvExactlyCode s buf offset len deadline
    = liftIO $ do True <- checkRange buf offset len
                    | False => pure (negate einval)
                  readExactlyLoop (connOf s) (fdOf s) buf offset len deadline 0

-- ---------------------------------------------------------------------------
-- Receiving and sending

fromCode : HasIO io => TLSSocket -> Int -> (Int -> a) -> io (Either TLSError a)
fromCode s r f = if r < 0 then Left <$> codeError s r else pure (Right (f r))

||| Receive at most `len` bytes into the buffer from `offset`, waiting until
||| some come or until the deadline: the number of bytes, 0 at the end of
||| the TLS stream (close_notify).  A stream that ends without close_notify
||| is `UnexpectedEOF`.
export covering
recv : HasIO io => TLSSocket -> Buffer -> (offset, len : Int) ->
       (deadline : Maybe Int) -> io (Either TLSError Int)
recv s buf offset len deadline
    = do r <- recvCode s buf offset len (deadlineCode deadline)
         fromCode s r id

||| Send at most `len` bytes of the buffer from `offset`: the number of
||| bytes sent, maybe fewer than `len` (see `sendAll`).
export covering
send : HasIO io => TLSSocket -> Buffer -> (offset, len : Int) ->
       (deadline : Maybe Int) -> io (Either TLSError Int)
send s buf offset len deadline
    = do r <- sendCode s buf offset len (deadlineCode deadline)
         fromCode s r id

||| Send all `len` bytes of the buffer from `offset`.
export covering
sendAll : HasIO io => TLSSocket -> Buffer -> (offset, len : Int) ->
          (deadline : Maybe Int) -> io (Either TLSError ())
sendAll s buf offset len deadline
    = do r <- sendAllCode s buf offset len (deadlineCode deadline)
         fromCode s r (const ())

||| Send all of two ranges, one after the other.
export covering
sendAll2 : HasIO io => TLSSocket ->
           Buffer -> (offset1, len1 : Int) ->
           Buffer -> (offset2, len2 : Int) ->
           (deadline : Maybe Int) -> io (Either TLSError ())
sendAll2 s b1 o1 l1 b2 o2 l2 deadline
    = do r <- sendAll2Code s b1 o1 l1 b2 o2 l2 (deadlineCode deadline)
         fromCode s r (const ())

||| Receive `len` bytes into the buffer from `offset`, unless the TLS stream
||| ends first: the number of bytes received.
export covering
recvExactly : HasIO io => TLSSocket -> Buffer -> (offset, len : Int) ->
              (deadline : Maybe Int) -> io (Either TLSError Int)
recvExactly s buf offset len deadline
    = do r <- recvExactlyCode s buf offset len (deadlineCode deadline)
         fromCode s r id

-- ---------------------------------------------------------------------------
-- What was negotiated

nonEmpty : String -> Maybe String
nonEmpty "" = Nothing
nonEmpty s = Just s

||| The version of the protocol ("TLSv1.3", "TLSv1.2"), "" before the
||| handshake or after `close`.
export
tlsVersion : HasIO io => TLSSocket -> io String
tlsVersion s = primIO $ prim__info (connOf s) 0

||| The name of the cipher suite ("TLS_AES_256_GCM_SHA384"), "" when there
||| is none.
export
cipherName : HasIO io => TLSSocket -> io String
cipherName s = primIO $ prim__info (connOf s) 1

||| The protocol selected with ALPN, if any.
export
alpnSelected : HasIO io => TLSSocket -> io (Maybe String)
alpnSelected s = nonEmpty <$> primIO (prim__info (connOf s) 2)

||| The name that the client asked for with SNI, if any (on both sides).
export
serverName : HasIO io => TLSSocket -> io (Maybe String)
serverName s = nonEmpty <$> primIO (prim__info (connOf s) 3)

||| A summary of a certificate, for logs.
public export
record CertificateInfo where
  constructor MkCertificateInfo
  ||| The subject, as in RFC 2253 ("CN=localhost,O=Example").
  subject : String
  ||| The issuer, as in RFC 2253.
  issuer : String
  ||| The start of the validity, in ISO 8601 ("2026-11-23 10:00:00Z").
  notBefore : String
  ||| The end of the validity, in ISO 8601.
  notAfter : String
  ||| The subject alternative names ("DNS:localhost", "IP:127.0.0.1",
  ||| "email:...", "URI:...").
  altNames : List String
  ||| The serial number, in hexadecimal.
  serial : String

export
Show CertificateInfo where
  show c = "subject=" ++ c.subject ++ " issuer=" ++ c.issuer
           ++ " valid " ++ c.notBefore ++ " to " ++ c.notAfter
           ++ " names=" ++ joinBy "," c.altNames

||| The certificate that the peer sent, if any (a server always sends one;
||| a client when the server asked and it had one).
export
peerCertificate : HasIO io => TLSSocket -> io (Maybe CertificateInfo)
peerCertificate s
    = do has <- primIO $ prim__info (connOf s) 4
         if has == "" then pure Nothing else do
           subj <- field 0
           iss <- field 1
           from <- field 2
           to <- field 3
           names <- field 4
           ser <- field 5
           pure $ Just $ MkCertificateInfo subj iss from to
                           (if names == "" then [] else forget (split (== ',') names))
                           ser
  where
    field : Int -> io String
    field n = primIO $ prim__peerCert (connOf s) n

||| The version of OpenSSL that the program runs with.
export
openSSLVersion : String
openSSLVersion = unsafePerformIO $ primIO prim__opensslVersion
