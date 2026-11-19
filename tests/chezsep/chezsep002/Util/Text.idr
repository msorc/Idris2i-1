module Util.Text

import Data.String

export
pad : Nat -> String -> String
pad n s = replicate (minus n (length s)) ' ' ++ s

export
commas : List String -> String
commas = joinBy ", "
