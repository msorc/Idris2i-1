module Foo

%foreign "C:foo_twice,,foo.h"
prim__fooTwice : Int -> Int

export
fooTwice : Int -> Int
fooTwice = prim__fooTwice
