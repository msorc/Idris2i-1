-- The candidates fail at different places: each keeps its own excerpt
namespace A
  export
  op : Nat -> Bool -> Bool
  op _ b = b

namespace B
  export
  op : String -> Bool
  op s = s == ""

test : Nat -> Bool
test n = op n n
