module Main

import Answer

-- the same directive again: the archive is linked once
%cg refc refc-archive=libanswer.a

main : IO ()
main = printLn (answerPlus 0)
