import System.FFI

Named : Type
Named = Struct "named" [("name", String), ("x", Int)]

%foreign "C:mkNamed,libnamed"
mkNamed : PrimIO Named

main : IO ()
main = do n <- primIO mkNamed
          printLn (the Int (getField n "x"))
