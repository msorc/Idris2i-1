-- expect: E0802
-- The fields of a tuple are unrestricted, so a linear name may not go there.

dup : (1 x : a) -> (a, a)
dup x = (x, x)
