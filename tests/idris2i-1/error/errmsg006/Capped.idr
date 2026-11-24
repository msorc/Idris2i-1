-- More failed candidates than are shown by default
namespace A
  export
  val : Int
  val = 1
namespace B
  export
  val : String
  val = "1"
namespace C
  export
  val : Char
  val = '1'
namespace D
  export
  val : Double
  val = 1.0
namespace E
  export
  val : Bool
  val = True
namespace F
  export
  val : List Nat
  val = [1]
namespace G
  export
  val : Maybe Nat
  val = Just 1

n : Nat
n = val
