module Main

%foreign "C:answer,libanswer,answer.h"
answer : Int -> Int

main : IO ()
main = printLn (answer 1)
