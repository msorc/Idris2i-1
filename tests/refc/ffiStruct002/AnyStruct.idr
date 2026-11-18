import System.FFI

%foreign "C:mkPoint,libpoint"
mkPoint : PrimIO (Struct "point" [("x", Int), ("y", Int)])

-- The name of the struct is an argument
getX : {sn : String} -> Struct sn [("x", Int), ("y", Int)] -> Int
getX s = getField s "x"

main : IO ()
main = do p <- primIO mkPoint
          printLn (getX p)
