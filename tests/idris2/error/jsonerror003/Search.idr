module Search

data Foo = MkFoo

data Box a = MkBox a

Show a => Show (Box a) where
  show (MkBox x) = show x

nested : String
nested = show [MkBox MkFoo]

interface Describe a where
  describe : a -> String

Describe Int where
  describe _ = "Int"

[other] Describe Int where
  describe _ = "other Int"

%hint
otherInt : Describe Int
otherInt = other

ambiguous : Int -> String
ambiguous i = describe i
