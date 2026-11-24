-- literals whose conversion does not reduce to a constructor form
%foreign "C:opaque_int, libopaque" "scheme:opaque-int" "javascript:lambda:x=>x"
prim__opaque : Integer -> Integer

data Big = MkBig Integer

Num Big where
  fromInteger x = MkBig (prim__opaque x)
  a + b = a
  a * b = a

f : Big -> String
f 3 = "three"
f _ = "other"

data Name = MkName String

%foreign "C:opaque_string, libopaque" "scheme:opaque-string" "javascript:lambda:x=>x"
prim__opaqueStr : String -> String

FromString Name where
  fromString s = MkName (prim__opaqueStr s)

g : Name -> String
g "x" = "x"
g _ = "other"
