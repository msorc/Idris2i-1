module Main


data SomePointer : Type where

%foreign "C:idris2i_1_getNull, libidris2i_1_support, idris_support.h"
getTypedPointer : PrimIO (Ptr SomePointer)


freeTypedPointer : Ptr SomePointer -> IO ()
freeTypedPointer ptr = do
    putStrLn "allocated (Ptr t) freed"
    -- we could free the pointer here. However, since ptr is the NULL pointer, we just simulate it


%foreign "C:idris2i_1_getNull, libidris2i_1_support, idris_support.h"
getSomeAnyPointer : PrimIO (AnyPtr)

freeAnyPointer : AnyPtr -> IO ()
freeAnyPointer ptr = do
    putStrLn "allocated AnyPtr freed"
    -- we could free the pointer here. However, since ptr is the NULL pointer, we just simulate it



main : IO ()
main = do
    ptr <- primIO $ getTypedPointer
    gcPtr <- onCollect ptr freeTypedPointer
    anyptr <- primIO $ getSomeAnyPointer
    gcAnyPtr <- onCollectAny anyptr freeAnyPointer
    pure ()
