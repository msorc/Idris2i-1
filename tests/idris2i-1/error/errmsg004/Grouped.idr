-- Every candidate fails on the same argument: one excerpt for all of them
namespace A
  export
  size : List a -> Nat
  size = length

namespace B
  export
  size : String -> Nat
  size = length

namespace C
  export
  size : Maybe a -> Nat
  size _ = 1

total' : Bool -> Nat
total' b = size b
