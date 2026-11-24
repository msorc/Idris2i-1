namespace A
  export
  f : Nat -> Nat -> Nat
  f x y = x + y

namespace B
  export
  f : String -> String -> String
  f x y = x ++ y

wrong : Bool
wrong = f 1 (the Bool True)
