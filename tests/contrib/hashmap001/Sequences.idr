module Sequences

import Data.Hashable
import Data.List1
import Data.SnocList
import Data.Vect

import Keys

export
checkSequences : IO ()
checkSequences = do
  check "hash of Vect, List, SnocList and List1 agree"
    (let l = the (List Int) [4, 5, 6] in
       hash l == hash (the (Vect 3 Int) [4, 5, 6])
    && hash l == hash (the (SnocList Int) [<4, 5, 6])
    && hash l == hash (the (List1 Int) (4 ::: [5, 6])))
