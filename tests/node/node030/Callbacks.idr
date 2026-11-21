module Callbacks

import Data.IORef

-- With the trampoline, the functions given to foreign code are wrapped: the
-- same function must arrive as the same JavaScript function each time (so
-- that the foreign code can remove a callback that it was given, as
-- removeEventListener does), with the length of the original.

%foreign "javascript:lambda: (f, w) => { globalThis.handlers = globalThis.handlers || new Set(); globalThis.handlers.add(f); globalThis.lengths = (globalThis.lengths || []).concat([f.length]) }"
prim__on : (Int -> PrimIO ()) -> PrimIO ()

%foreign "javascript:lambda: (f, w) => { globalThis.handlers.delete(f) }"
prim__off : (Int -> PrimIO ()) -> PrimIO ()

%foreign "javascript:lambda: (n, w) => { for (const h of globalThis.handlers) h(n)(w) }"
prim__fire : Int -> PrimIO ()

%foreign "javascript:lambda: (w) => 'handlers left: ' + globalThis.handlers.size + ', callback lengths: ' + globalThis.lengths.join(' ')"
prim__info : PrimIO String

-- the functions that a function given to foreign code returns are wrapped
-- too, and keep their length as well
%foreign "javascript:lambda: (f, w) => { const a = f(1), b = f(2); return f.length + ' ' + a.length + ' ' + a(3) + ' ' + b(4) }"
prim__curried : (Int -> Int -> Int) -> PrimIO String

-- the foreign code can wrap again a function that it was given, which
-- changes nothing
%foreign "javascript:lambda: (f, w) => String(__resFn(f) === f)"
prim__rewrap : (Int -> Int) -> PrimIO String

handler : Int -> PrimIO ()
handler n = toPrim (putStrLn ("handler " ++ show n))

other : Int -> PrimIO ()
other n = toPrim (putStrLn ("other " ++ show n))

add : Int -> Int -> Int
add x y = x + y

main : IO ()
main = do
  ref <- newIORef handler
  h <- readIORef ref
  primIO (prim__on h)
  primIO (prim__on other)
  primIO (prim__on h)
  primIO (prim__fire 1)
  h' <- readIORef ref
  primIO (prim__off h')
  primIO (prim__fire 2)
  primIO (prim__off other)
  putStrLn !(primIO prim__info)
  putStrLn !(primIO (prim__curried add))
  putStrLn !(primIO (prim__rewrap (add 1)))
