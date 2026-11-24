module Lib

public export
data T = A | B

public export
interface Foo a where
  partial
  foo : a -> a

export
Foo T where
  foo A = B

-- Covering (the default), and so accepted
export
useFoo : T -> T
useFoo = foo
