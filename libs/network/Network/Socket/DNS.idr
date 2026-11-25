||| Name resolution: the numeric addresses of a host name.
|||
||| On the RefC back end, getaddrinfo(3), which blocks, runs on a thread of
||| the pool of blocking calls of the runtime while the calling green thread
||| parks (the other threads of its worker keep running).  On the Chez back
||| end it blocks the calling OS thread.  A numeric host is
||| converted at once, without a lookup.
module Network.Socket.DNS

import Data.List
import Network.Socket.Address

%default total

netC : String -> String
netC fn = "C:\{fn}, libidris2i_1_support, idris_net_async.h"

%foreign netC "idrnet_async_strdup"
prim__strdup : String -> PrimIO AnyPtr

%foreign "C__collect_safe:idrnet_async_resolve, libidris2i_1_support, idris_net_async.h"
         "C:idrnet_async_resolve, libidris2i_1_support, idris_net_async.h"
prim__resolve : AnyPtr -> Int -> Int -> PrimIO AnyPtr

%foreign netC "idrnet_async_resolve_status"
prim__status : AnyPtr -> PrimIO Int

%foreign netC "idrnet_async_resolve_error"
prim__error : AnyPtr -> PrimIO String

%foreign netC "idrnet_async_resolve_count"
prim__count : AnyPtr -> PrimIO Int

%foreign netC "idrnet_async_resolve_family"
prim__family : AnyPtr -> Int -> PrimIO Int

%foreign netC "idrnet_async_resolve_port"
prim__port : AnyPtr -> Int -> PrimIO Int

%foreign netC "idrnet_async_resolve_host"
prim__host : AnyPtr -> Int -> PrimIO String

%foreign netC "idrnet_async_resolve_free"
prim__free : AnyPtr -> PrimIO ()

||| The addresses of `host` (a name, or a numeric address), with the port,
||| in the order of getaddrinfo(3) (the preferred one first): IPv4 and IPv6
||| ones, or only those of the family given.  Without a family, only the
||| families that the machine has an address of are asked for, as
||| `AI_ADDRCONFIG` does.  `Left` the message of getaddrinfo when the name
||| cannot be resolved.
export
resolve : HasIO io => (host : String) -> (port : Int) -> Maybe Family ->
          io (Either String (List SockAddr))
resolve host port fam
    = do h <- primIO $ prim__strdup host
         res <- primIO $ prim__resolve h port (case fam of
                                                 Nothing => 0
                                                 Just f => familyCode f)
         status <- primIO $ prim__status res
         if status /= 0
            then do msg <- primIO $ prim__error res
                    primIO $ prim__free res
                    pure (Left msg)
            else do n <- primIO $ prim__count res
                    addrs <- collect res (n - 1) []
                    primIO $ prim__free res
                    pure (Right addrs)
  where
    -- the entries from `i` down to 0, put in front of `acc`
    collect : AnyPtr -> Int -> List SockAddr -> io (List SockAddr)
    collect res i acc
        = if i < 0 then pure acc else do
            f <- primIO $ prim__family res i
            p <- primIO $ prim__port res i
            h <- primIO $ prim__host res i
            let acc' = case familyOfCode f of
                         Just fam => mkSockAddr fam h p :: acc
                         Nothing => acc
            collect res (assert_smaller i (i - 1)) acc'
