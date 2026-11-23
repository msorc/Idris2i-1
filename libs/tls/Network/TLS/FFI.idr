||| The C functions of the tls library (`c/idris_tls.h`), as they are.
|||
||| This module is the layer under `Network.TLS`, which is the one to use
||| (it does not re-export this one): the functions here do not check their
||| arguments, and each one does a single step that may have to be retried
||| after a wait.
module Network.TLS.FFI

import Data.Buffer

-- How to link the C part of the library with the RefC back end: its
-- archive (in the `lib` directory of the package, or the current one), and
-- OpenSSL as pkg-config finds it.  The Scheme back ends load the shared
-- library of the foreign specifiers below.
%cg refc refc-archive=libidris2_tls.a
%cg refc refc-pkg-config=openssl

%default total

tlsC : String -> String
tlsC fn = "C:\{fn},libidris2_tls,idris_tls.h"

-- ---------------------------------------------------------------------------
-- Contexts

||| `idris_tls_ctx_new` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_ctx_new"
prim__ctxNew : (isServer : Int) -> (minVersion : Int) -> PrimIO AnyPtr

||| `idris_tls_ctx_free` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_ctx_free"
prim__ctxFree : AnyPtr -> PrimIO ()

||| `idris_tls_ctx_error` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_ctx_error"
prim__ctxError : GCAnyPtr -> PrimIO String

||| `idris_tls_ctx_use_system_trust` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_ctx_use_system_trust"
prim__ctxUseSystemTrust : GCAnyPtr -> PrimIO Int

||| `idris_tls_ctx_trust` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_ctx_trust"
prim__ctxTrust : GCAnyPtr -> (caFile : String) -> (caDir : String) -> PrimIO Int

||| `idris_tls_ctx_trust_pem` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_ctx_trust_pem"
prim__ctxTrustPEM : GCAnyPtr -> String -> PrimIO Int

||| `idris_tls_ctx_set_verify` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_ctx_set_verify"
prim__ctxSetVerify : GCAnyPtr -> Int -> PrimIO Int

||| `idris_tls_ctx_use_cert` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_ctx_use_cert"
prim__ctxUseCert : GCAnyPtr -> (chain : String) -> (key : String) -> (isText : Int) -> PrimIO Int

||| `idris_tls_ctx_add_sni_cert` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_ctx_add_sni_cert"
prim__ctxAddSNICert : GCAnyPtr -> (name : String) -> (chain : String) -> (key : String) ->
                      (isText : Int) -> PrimIO Int

||| `idris_tls_ctx_set_alpn` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_ctx_set_alpn"
prim__ctxSetALPN : GCAnyPtr -> (protocols : String) -> (required : Int) -> PrimIO Int

-- ---------------------------------------------------------------------------
-- Connections

||| `idris_tls_conn_new` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_conn_new"
prim__connNew : GCAnyPtr -> (fd : Int) -> (host : String) -> (verifyHost : Int) -> PrimIO AnyPtr

||| `idris_tls_conn_status` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_conn_status"
prim__connStatus : GCAnyPtr -> PrimIO Int

||| `idris_tls_conn_free` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_conn_free"
prim__connFree : AnyPtr -> PrimIO ()

||| `idris_tls_conn_release` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_conn_release"
prim__connRelease : GCAnyPtr -> PrimIO Int

||| `idris_tls_handshake` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_handshake"
prim__handshake : GCAnyPtr -> PrimIO Int

||| `idris_tls_read` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_read"
prim__read : GCAnyPtr -> Buffer -> (offset : Int) -> (len : Int) -> PrimIO Int

||| `idris_tls_write` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_write"
prim__write : GCAnyPtr -> Buffer -> (offset : Int) -> (len : Int) -> PrimIO Int

||| `idris_tls_write2` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_write2"
prim__write2 : GCAnyPtr -> Buffer -> (offset1 : Int) -> (len1 : Int) ->
               Buffer -> (offset2 : Int) -> (len2 : Int) -> PrimIO Int

||| `idris_tls_shutdown` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_shutdown"
prim__shutdown : GCAnyPtr -> PrimIO Int

||| `idris_tls_conn_error` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_conn_error"
prim__connError : GCAnyPtr -> PrimIO String

||| `idris_tls_verify_result` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_verify_result"
prim__verifyResult : GCAnyPtr -> PrimIO Int

||| `idris_tls_info` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_info"
prim__info : GCAnyPtr -> Int -> PrimIO String

||| `idris_tls_peer_cert` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_peer_cert"
prim__peerCert : GCAnyPtr -> Int -> PrimIO String

||| `idris_tls_code_message` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_code_message"
prim__codeMessage : Int -> PrimIO String

||| `idris_tls_openssl_version` (see `c/idris_tls.h`).
export
%foreign tlsC "idris_tls_openssl_version"
prim__opensslVersion : PrimIO String

-- ---------------------------------------------------------------------------
-- Waiting

||| The wait of `System.IO.Wait`, without its `Maybe` and result type: a
||| deadline below 0 is none; the result is 1 ready, 0 deadline, or -errno.
export
%foreign "RefC:idris2_ioWait"
         "C__collect_safe:idris2_fdWaitBlocking, libidris2_support, idris_fd.h"
         "C:idris2_fdWaitBlocking, libidris2_support, idris_fd.h"
prim__wait : (fd : Int) -> (event : Int) -> (deadline : Int64) -> PrimIO Int
