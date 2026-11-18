import System.FFI

Point : Type
Point = Struct "point" [("x", Int), ("y", Int)]

main : IO ()
main = do p <- malloc 8
          let pt : Point = believe_me p
          setField pt "x" (the Int 1)
          free p
