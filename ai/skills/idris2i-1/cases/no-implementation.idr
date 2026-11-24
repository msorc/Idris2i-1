-- expect: E0401
data T = A | B

same : T -> T -> Bool
same x y = x == y
