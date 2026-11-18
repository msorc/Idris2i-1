import Data.String
import System.FFI

lib : String -> String
lib fn = "C:" ++ fn ++ ",libstructs,structs.h"

Point : Type
Point = Struct "point" [("x", Int), ("y", Int)]

NamedPoint : Type
NamedPoint = Struct "namedpoint" [("name", Ptr String), ("pt", Point)]

Fields : Type
Fields = Struct "fields"
           [ ("c", Char), ("i", Int)
           , ("i8", Int8), ("i16", Int16), ("i32", Int32), ("i64", Int64)
           , ("b8", Bits8), ("b16", Bits16), ("b32", Bits32), ("b64", Bits64)
           , ("d", Double), ("p", AnyPtr), ("last", Char) ]

%foreign (lib "mkPoint")
mkPoint : Int -> Int -> Point

%foreign (lib "freePoint")
freePoint : Point -> PrimIO ()

%foreign (lib "sumPoint")
sumPoint : Point -> PrimIO Int

%foreign (lib "asPoint")
asPoint : AnyPtr -> Point

%foreign (lib "sizeofPoint")
sizeofPoint : Int

%foreign (lib "mkNamedPoint")
mkNamedPoint : String -> Point -> PrimIO NamedPoint

%foreign (lib "freeNamedPoint")
freeNamedPoint : NamedPoint -> PrimIO ()

%foreign (lib "getString")
getStr : Ptr String -> String

%foreign (lib "mkFields")
mkFields : PrimIO Fields

%foreign (lib "freeFields")
freeFields : Fields -> PrimIO ()

%foreign (lib "showFields")
showFields : Fields -> PrimIO ()

showPoint : Point -> String
showPoint pt
    = let x : Int = getField pt "x"
          y : Int = getField pt "y" in
          show (x, y)

showNamedPoint : NamedPoint -> String
showNamedPoint np
    = let name : String = getStr (getField np "name")
          pt : Point = getField np "pt" in
          show name ++ ": " ++ showPoint pt

showAll : Fields -> String
showAll f
    = unwords
        [ show (the Char (getField f "c")), show (the Int (getField f "i"))
        , show (the Int8 (getField f "i8")), show (the Int16 (getField f "i16"))
        , show (the Int32 (getField f "i32")), show (the Int64 (getField f "i64"))
        , show (the Bits8 (getField f "b8")), show (the Bits16 (getField f "b16"))
        , show (the Bits32 (getField f "b32")), show (the Bits64 (getField f "b64"))
        , show (the Double (getField f "d"))
        , if prim__nullAnyPtr (getField f "p") /= 0 then "null" else "not null"
        , show (the Char (getField f "last")) ]

-- The struct is not looked at again after the last use of a field
swap : Point -> IO ()
swap pt
    = do let x : Int = getField pt "x"
         setField pt "x" (the Int (getField pt "y"))
         setField pt "y" x

main : IO ()
main = do
    -- a struct that a C function returns
    let pt = mkPoint 20 30
    setField pt "x" (the Int 40)
    putStrLn $ showPoint pt
    -- a struct passed to a C function
    printLn !(primIO $ sumPoint pt)
    swap pt
    putStrLn $ showPoint pt

    -- a struct in a struct (a pointer)
    np <- primIO $ mkNamedPoint "Here" pt
    putStrLn $ showNamedPoint np
    setField pt "y" (the Int 50)
    putStrLn $ showNamedPoint np

    -- a struct allocated in Idris
    mem <- malloc sizeofPoint
    let pt2 = asPoint mem
    setField pt2 "x" (the Int 1)
    setField pt2 "y" (the Int (-2))
    putStrLn $ showPoint pt2
    printLn !(primIO $ sumPoint pt2)
    setField np "pt" pt2
    putStrLn $ showNamedPoint np
    primIO $ freeNamedPoint np
    free mem
    primIO $ freePoint pt

    -- a field of each type
    f <- primIO mkFields
    putStrLn $ showAll f
    setField f "c" 'b'
    setField f "i" (the Int 2147483647)
    setField f "i8" (the Int8 127)
    setField f "i16" (the Int16 (-32768))
    setField f "i32" (the Int32 2147483647)
    setField f "i64" (the Int64 (-9223372036854775808))
    setField f "b8" (the Bits8 255)
    setField f "b16" (the Bits16 65535)
    setField f "b32" (the Bits32 4294967295)
    setField f "b64" (the Bits64 18446744073709551615)
    setField f "d" (the Double 1.25)
    q <- malloc 1
    setField f "p" q
    setField f "last" 'y'
    putStrLn $ showAll f
    primIO $ showFields f
    primIO $ freeFields f
    free q
