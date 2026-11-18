import System.FFI

%foreign "C:mkPoint,libpoint"
mkPoint : PrimIO (Struct "point" [("x", Int), ("y", Int)])

%foreign "C:freePoint,libpoint"
freePoint : Struct "point" [("x", Double), ("y", Double)] -> PrimIO ()

main : IO ()
main = do p <- primIO mkPoint
          printLn (the Int (getField p "x"))
          primIO (freePoint (believe_me p))
