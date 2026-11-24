module Fail

-- F imports A privately: A's names are not visible here
import F

bad : Nat
bad = Y.f (Y.MkT 1)
