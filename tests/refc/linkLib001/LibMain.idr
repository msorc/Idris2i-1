module LibMain

import Lib

main : IO ()
main = printLn (fooTwice 50)
