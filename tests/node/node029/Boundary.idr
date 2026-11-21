module Boundary

-- Idris functions that JavaScript calls, but not as arguments of a function
-- type of a foreign function: with the trampoline, they must still return
-- their value, never a pending call (an object of class __TC).

-- `step` makes `n` nested tail calls to a function that is not known
-- statically (the function in the box), then returns 42.
data Box = MkBox (Box -> Int -> Int)

step : Box -> Int -> Int
step b n = case b of
  MkBox k => if n <= 0 then 42 else k b (n - 1)

-- the same, which throws a JavaScript exception at the end
%foreign "javascript:lambda: (x) => { throw new Error('boom') }"
prim__throw : Int -> Int

stepThrow : Box -> Int -> Int
stepThrow b n = case b of
  MkBox k => if n <= 0 then prim__throw n else k b (n - 1)

%foreign "javascript:lambda: (w) => { globalThis.describe = r => (typeof r === 'bigint' || typeof r === 'number') ? ('value ' + r) : ('not a value: ' + (r && r.constructor ? r.constructor.name : String(r))) }"
prim__setUp : PrimIO ()

-- a closure in an AnyPtr, called by the foreign function it is given to
%foreign "javascript:lambda: (p, x, w) => describe(p(x))"
prim__callPtr : AnyPtr -> Int -> PrimIO String

-- the same, which the foreign function wraps in `__resFn`, to run it with
-- the trampoline (without it, the closure makes its tail calls directly, so
-- as many of them as the stack holds)
%foreign "javascript:lambda: (p, x, w) => describe(__resFn(p)(x))"
prim__callPtrRes : AnyPtr -> Int -> PrimIO String

-- a closure stored by JavaScript code, and called by another foreign
-- function or from the event loop
%foreign "javascript:lambda: (p, w) => { globalThis.stored = [p] }"
prim__store : AnyPtr -> PrimIO ()

%foreign "javascript:lambda: (x, w) => describe(globalThis.stored[0](x))"
prim__callStored : Int -> PrimIO String

%foreign "javascript:lambda: (x, w) => { setTimeout(() => console.log('from the event loop, ' + x + ': ' + describe(globalThis.stored[0](x))), 0) }"
prim__callStoredLater : Int -> PrimIO ()

-- a function argument, whose call throws through the nested calls
%foreign "javascript:lambda: (f, x, w) => { try { return 'returned ' + f(x) } catch (e) { return 'caught ' + e.message } }"
prim__try : (Int -> Int) -> Int -> PrimIO String

-- the count of the nested calls of the trampoline (internal)
%foreign "javascript:lambda: (w) => __tc.depth"
prim__depth : PrimIO Int

tryThrow : Int -> IO ()
tryThrow n = do
  d <- primIO prim__depth
  s <- primIO (prim__try (stepThrow (MkBox stepThrow)) n)
  d' <- primIO prim__depth
  putStrLn ("exception after " ++ show n ++ ": " ++ s
            ++ ", count restored: " ++ show (d == d'))

callPtr : Int -> IO ()
callPtr n = do
  s <- primIO (prim__callPtr (believe_me (step (MkBox step))) n)
  putStrLn ("in an AnyPtr, " ++ show n ++ ": " ++ s)

callPtrRes : Int -> IO ()
callPtrRes n = do
  s <- primIO (prim__callPtrRes (believe_me (step (MkBox step))) n)
  putStrLn ("in an AnyPtr, with __resFn, " ++ show n ++ ": " ++ s)

callStored : Int -> IO ()
callStored n = do
  s <- primIO (prim__callStored n)
  putStrLn ("stored, " ++ show n ++ ": " ++ s)


main : IO ()
main = do
  primIO prim__setUp
  callPtr 3
  callPtr 60
  callPtr 100
  callPtr 1000
  callPtrRes 1000000
  primIO (prim__store (believe_me (step (MkBox step))))
  callStored 100
  callStored 1000
  -- an exception thrown through the nested calls of the trampoline must not
  -- leave them counted
  tryThrow 62
  callPtr 3
  tryThrow 200
  callPtr 3
  callStored 3
  primIO (prim__callStoredLater 100)
