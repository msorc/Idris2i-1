||| Numeric socket addresses, for `Network.Socket.Async` and
||| `Network.Socket.DNS`.
|||
||| An address holds its host as text, in numeric form only ("127.0.0.1",
||| "::1", "fe80::1%eth0"): nothing that takes an address looks a name up.
||| Names are resolved by `Network.Socket.DNS.resolve`.
module Network.Socket.Address

%default total

||| An address family.
public export
data Family = Unix | IPv4 | IPv6

export
Show Family where
  show Unix = "Unix"
  show IPv4 = "IPv4"
  show IPv6 = "IPv6"

export
Eq Family where
  Unix == Unix = True
  IPv4 == IPv4 = True
  IPv6 == IPv6 = True
  _ == _ = False

||| The code of a family for the C functions of `idris_net_async.h`.
export
familyCode : Family -> Int
familyCode Unix = 1
familyCode IPv4 = 4
familyCode IPv6 = 6

||| The family of a code of `idris_net_async.h`.
export
familyOfCode : Int -> Maybe Family
familyOfCode 1 = Just Unix
familyOfCode 4 = Just IPv4
familyOfCode 6 = Just IPv6
familyOfCode _ = Nothing

||| A socket address.
public export
data SockAddr
  = ||| An IPv4 address, numeric ("127.0.0.1"; "" for any address when
    ||| binding), and a port.
    Inet String Int
  | ||| An IPv6 address, numeric ("::1", "fe80::1%eth0"; "" for any address
    ||| when binding), and a port.
    Inet6 String Int
  | ||| The path of a Unix-domain socket.
    UnixPath String

||| Shows the address as "127.0.0.1:80", "[::1]:80" or "unix:/path".
export
Show SockAddr where
  show (Inet h p) = h ++ ":" ++ show p
  show (Inet6 h p) = "[" ++ h ++ "]:" ++ show p
  show (UnixPath p) = "unix:" ++ p

export
Eq SockAddr where
  Inet h p == Inet h' p' = h == h' && p == p'
  Inet6 h p == Inet6 h' p' = h == h' && p == p'
  UnixPath p == UnixPath p' = p == p'
  _ == _ = False

||| The family of an address.
export
addrFamily : SockAddr -> Family
addrFamily (Inet _ _) = IPv4
addrFamily (Inet6 _ _) = IPv6
addrFamily (UnixPath _) = Unix

||| The host of an address (the path of a Unix socket).
export
addrHost : SockAddr -> String
addrHost (Inet h _) = h
addrHost (Inet6 h _) = h
addrHost (UnixPath p) = p

||| The port of an address (0 for a Unix socket).
export
addrPort : SockAddr -> Int
addrPort (Inet _ p) = p
addrPort (Inet6 _ p) = p
addrPort (UnixPath _) = 0

||| The same address with another port (a Unix address is unchanged).
export
withPort : Int -> SockAddr -> SockAddr
withPort p (Inet h _) = Inet h p
withPort p (Inet6 h _) = Inet6 h p
withPort _ a@(UnixPath _) = a

||| A numeric host and a port: an IPv6 address when the host has a colon,
||| an IPv4 address otherwise.  Whether the host is a valid address is
||| checked when the address is used.
export
numericAddr : (host : String) -> (port : Int) -> SockAddr
numericAddr host port
    = if any (== ':') (unpack host) then Inet6 host port else Inet host port

||| The address of a family, its numeric host and its port (for C results).
export
mkSockAddr : Family -> (host : String) -> (port : Int) -> SockAddr
mkSockAddr Unix h _ = UnixPath h
mkSockAddr IPv4 h p = Inet h p
mkSockAddr IPv6 h p = Inet6 h p
