||| The names of `Ab` and `BA` (and of `Ac` and `BB`) used to hash alike, so
||| the copy of `pick` specialised by one was used for the other.
module Collide

data T = Ab | BA | Ac | BB

%spec x
pick : (x : T) -> Int -> Int
pick Ab n = n + 1
pick BA n = n + 2
pick Ac n = n + 3
pick BB n = n + 4

record Wrap where
  constructor MkWrap
  ab : T
  ba : T

%spec w
pickBoth : (w : Wrap) -> Int -> Int
pickBoth w n = pick w.ab n * 10 + pick w.ba n

main : IO ()
main = do
  printLn (pick Ab 0)
  printLn (pick BA 0)
  printLn (pick Ac 0)
  printLn (pick BB 0)
  printLn (pickBoth (MkWrap Ab BA) 0)
  printLn (pickBoth (MkWrap BA Ab) 0)
