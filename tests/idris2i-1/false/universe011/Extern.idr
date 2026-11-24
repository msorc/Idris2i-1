||| A primitive (`%extern`, `%foreign`) has no body: each use renames the
||| universes of its declared type afresh (its type is an assumption, as for
||| any primitive), so one can be used at its own type, which is above its
||| own universe of types (as Coq's polymorphic identity can).
module Extern

%default total

%extern prim__ident : (0 a : Type) -> a -> a

selfApplied : (0 a : Type) -> a -> a
selfApplied = prim__ident ((0 a : Type) -> a -> a) prim__ident
