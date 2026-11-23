-- expect: E0601
data T = A | B | C

name : T -> String
name A = "a"
name B = "b"
