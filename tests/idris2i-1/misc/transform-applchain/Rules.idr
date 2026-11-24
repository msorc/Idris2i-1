module Rules

-- Rules whose right-hand sides have binders and holes solved late, and a rule
-- on a method after the implementation of the method, used from Main.

public export
interface Describe a where
  describe : a -> String

public export
Describe Int where
  describe _ = "the implementation"

-- Tried before the rule that the implementation adds (which makes `describe`
-- at `Int` a call of the implementation's function), here and in a module
-- that imports this one.
%transform "describeInt" describe {a = Int} x = "the rule"

export %noinline
scale : List a -> List a
scale xs = xs

-- A lambda, whose type has a variable of the rule.
%transform "scaleRule" scale xs = maybe [] (\ys => ys ++ ys) (Just xs)

export %noinline
pairUp : a -> List a -> Maybe (a, List a)
pairUp _ _ = Nothing

-- A function type in an implicit argument (of `pure`, for `MkPair`).
%transform "pairUpRule" pairUp x xs = [| MkPair (Just x) (Just xs) |]

-- The implicit arguments of `map` and `.` are holes solved after they are
-- made.
export %noinline
getAll : (a -> Maybe b) -> List a -> IO (Maybe (List b))
getAll _ _ = pure Nothing

%transform "getAllRule" getAll f xs = map sequence (ioTraverseList (pure . f) xs)

export
inside : String
inside = describe (the Int 1)
