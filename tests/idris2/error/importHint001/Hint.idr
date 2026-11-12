module Hint

import Data.Vect

-- exported by a module that is not imported
sorted : List Nat -> List Nat
sorted xs = sortBy compare xs

-- exported by several modules
infix_ : String -> String -> Bool
infix_ s t = isInfixOf s t

-- not defined anywhere
nowhere : Nat
nowhere = definitelyNotDefinedAnywhere 3
