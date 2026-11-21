module Main

import A

-- `f` is specialised by the same argument twice: the second time the copy
-- is made already.  Neither must let this module use what A does not export.
%spec g
f : (g : Int -> Int) -> List Int -> List Int
f g [] = []
f g (x :: xs) = g x :: f g xs

h : List Int -> List Int
h xs = f (+1) xs

h2 : List Int -> List Int
h2 xs = f (+1) xs

leak : Int
leak = A.secret

main : IO ()
main = printLn (h [1,2,3], h2 [1], leak)
