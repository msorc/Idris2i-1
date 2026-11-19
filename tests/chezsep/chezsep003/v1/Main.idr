module Main

import Lib.Mid
import Lib.Other

main : IO ()
main = putStrLn (other ++ " " ++ show mid ++ " v1")
