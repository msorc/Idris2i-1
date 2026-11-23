module Answer

-- Every program that imports this module links the archive, which the
-- package installs in its `lib` directory, with its header.
%cg refc refc-archive=libanswer.a

%foreign "C:answer_plus,,answer.h"
prim__answerPlus : Int -> Int

export
answerPlus : Int -> Int
answerPlus = prim__answerPlus
