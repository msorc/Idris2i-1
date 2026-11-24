module Why

-- Errors from a search for an implementation say why it failed

import Data.List

data Foo = MkFoo

data Box a = MkBox a

Show a => Show (Box a) where
  show (MkBox x) = show x

-- No implementation of the interface matches the type
noImpl : String
noImpl = show MkFoo

-- An implementation matches, but needs a constraint that fails, through
-- several implementations
nested : String
nested = show [MkBox MkFoo]

-- A long chain is cut short
deep : String
deep = show [Just (MkBox (MkBox (MkBox MkFoo)))]

-- The type is not known
unknown : String
unknown = show (cast 1)

-- A local implementation of the interface, for another type
interface Describe a where
  describe : a -> String

Describe Int where
  describe _ = "Int"

local : Describe Int => Bool -> String
local b = describe b

-- Several implementations match
[other] Describe Int where
  describe _ = "other Int"

%hint
otherInt : Describe Int
otherInt = other

ambiguous : Int -> String
ambiguous i = describe i

-- Several unnamed implementations match
interface Size a where
  size : a -> Nat

Size (List a) where
  size = length

Size (List Nat) where
  size = sum

twoSizes : List Nat -> Nat
twoSizes xs = size xs

-- A function's constraint fails
sorted : List Foo -> List Foo
sorted xs = sort xs
