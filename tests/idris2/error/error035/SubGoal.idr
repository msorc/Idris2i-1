-- When an implementation matches but one of its constraints can't be
-- found, the error should say which constraint is missing.

data Foo = MkFoo

data Box a = MkBox a

Show a => Show (Box a) where
  show (MkBox x) = show x

-- Direct: the List implementation matches, but needs Show Foo
direct : String
direct = show [MkFoo]

-- Nested: List -> Box -> Foo; the innermost missing constraint is reported
nested : String
nested = show [MkBox MkFoo]

-- Inside a pair
pair : String
pair = show (MkBox (the Nat 1), MkBox MkFoo)

-- No implementation matches at all: no extra line
noMatch : String
noMatch = show MkFoo

-- Missing constraint on a polymorphic argument
poly : a -> String
poly x = show (MkBox x)
