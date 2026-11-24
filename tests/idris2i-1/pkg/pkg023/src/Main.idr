module Main

import Dep

main : IO ()
main = putStrLn (greeting ++ " from the executable")
