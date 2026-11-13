module Main

import System.Concurrency

data SomePointer : Type where

%foreign "C:idris2_getNull, libidris2_support, idris_support.h"
getTypedPointer : PrimIO (Ptr SomePointer)

-- A borrowed list handed over to another thread: the forked action takes
-- it with it.
inThread : List String -> IO ThreadID
inThread xs = fork $ do
  pure ()
  putStrLn (concat xs)

-- Borrows the pointer: it must not be collected before the caller is done
-- with it.
look : GCPtr SomePointer -> String -> IO ()
look p msg = putStrLn msg

-- The pointer is collected after its last use, not during the call.
usePointer : IO ()
usePointer = do
  ptr <- primIO getTypedPointer
  gc <- onCollect ptr (\_ => putStrLn "collected")
  look gc "first look"
  look gc "second look"
  putStrLn "done with the pointer"

main : IO ()
main = do
  t <- inThread (map show [1 .. the Int 5])
  threadWait t
  ts <- traverse inThread [map show [6 .. the Int 8], ["nine"]]
  traverse_ (\t => threadWait t) ts
  usePointer
  putStrLn "end"
