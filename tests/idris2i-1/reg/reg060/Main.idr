-- Two modules (A.B, and A with a namespace A.B) with the same numbers for
-- their nested functions and with blocks in the namespace A.B: one replaced
-- the other.
import A.B
import A

main : IO ()
main = do
  printLn (f 5)
  printLn (g 5)
  putStrLn (show (MkW 2))
  putStrLn (show (MkV 2))
