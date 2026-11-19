||| A copy of `pick` by `R`, made here, called itself forever (and was taken
||| for the identity): `pick R 0` was 0.  No copy is made where the function
||| cannot be reduced.  A copy of `twice` by its function is made by putting
||| the function in place of its variable, which needs no reduction.
module Main

import Pick

%default total

next : Int -> Int
next n = n + 10

go : Int -> Int
go n = pick R n + twice next n + twice (pick Q) n

main : IO ()
main = do
  printLn (pick R 0)
  printLn (pick P 5)
  printLn (go 0)
