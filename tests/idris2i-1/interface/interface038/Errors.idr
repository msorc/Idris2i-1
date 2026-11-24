module Errors

-- Errors from searches in which candidates are rejected without unification
-- are the same as when every candidate was unified with the goal.

interface Describe a where
  describe : a -> String

Describe Int where
  describe _ = "Int"

Describe String where
  describe _ = "String"

Describe a => Describe (List a) where
  describe xs = "List " ++ concatMap describe xs

-- No implementation: every candidate is rejected
noImpl : Bool -> String
noImpl b = describe b

-- An implementation that matches, whose sub-goal fails
subGoal : List Bool -> String
subGoal xs = describe xs

-- Two candidates that match
[other] Describe Int where
  describe _ = "other Int"

%hint
otherInt : Describe Int
otherInt = other

ambiguous : Int -> String
ambiguous i = describe i
