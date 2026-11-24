-- #1326
%default total

data I : (Type -> Bool) -> Type where

J : Type -> (Type -> Bool)
J (I f) = f
J _ = \_ => True

JI : (f : Type -> Bool) -> J (I f) = f
JI f = Refl

q : (Bool -> Bool) -> (Type -> Bool)
q f x = f (J x x)

fix : (Bool -> Bool) -> Bool
fix f = J (I (q f)) (I (q f))

fixes : (f : Bool -> Bool) -> fix f = f (fix f)
fixes f = cong (\h => h (I (q f))) (JI (q f))

notfix : (b : Bool) -> b = not b -> Void
notfix True _ impossible
notfix False _ impossible

bad : Void
bad = notfix (fix not) (fixes not)
