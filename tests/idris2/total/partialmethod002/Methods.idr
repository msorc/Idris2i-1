-- User-defined interfaces whose implementation has a method that is not
-- total. Using the implementation in a total function is an error there.
%default total

data T = A | B

-- A method declared `partial`, with an implementation that is not covering
interface Foo a where
  partial
  foo : a -> a

Foo T where
  foo A = B

useFoo : T -> T
useFoo x = foo x

-- Total relative to the dictionary
absFoo : Foo a => a -> a
absFoo = foo

-- ...but whoever supplies the dictionary is not
useAbsFoo : T -> T
useAbsFoo = absFoo

-- A method declared `partial`, with an implementation that does not terminate
interface Loop a where
  partial
  loop : a -> a

Loop T where
  loop x = loop x

useLoop : T -> T
useLoop = loop

-- A method declared `covering`, with an implementation that does not terminate
interface Cov a where
  covering
  cov : a -> a

Cov T where
  cov x = cov x

useCov : T -> T
useCov = cov

covering
useCovCovering : T -> T
useCovCovering = cov

-- A method declared `partial`, with an implementation that is total: fine
Foo Bool where
  foo = not

useFooBool : Bool -> Bool
useFooBool = foo

-- Named implementations
[partialNamed] Foo Nat where
  foo Z = Z

useNamed : Nat -> Nat
useNamed = foo @{partialNamed}

[totalNamed] Foo Nat where
  foo = S

useTotalNamed : Nat -> Nat
useTotalNamed = foo @{totalNamed}

partial
honest : T -> T
honest = foo
