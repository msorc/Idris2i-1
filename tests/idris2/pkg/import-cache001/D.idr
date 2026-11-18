module D

import B

-- hidden in this module only
%hide A.g
%hide A.(+++)

private infixl 6 +++

(+++) : Nat -> Nat -> Nat
x +++ y = x + y

g : Nat
g = 100

public export
d : Nat
d = g +++ h
