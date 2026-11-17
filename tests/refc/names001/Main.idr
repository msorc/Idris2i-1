-- Two nested functions `go` in the namespace A.B, of two modules (A.B and A),
-- which have the same number in their modules.
import A.B
import A

main : IO ()
main = do
  printLn (f 5)
  printLn (g 5)
