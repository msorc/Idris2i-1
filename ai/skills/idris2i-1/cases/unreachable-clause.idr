-- expect: W0002
data T = A | B

zero : T
zero = A

isZero : T -> Bool
isZero zero = True
isZero _ = False
