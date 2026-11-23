-- expect: E0301
import Data.Vect

main : IO ()
main = for_ [1, 2, 3] $ \i => printLn (the Int i)
