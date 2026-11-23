-- expect: E0102
import Data.Vect

namespace Lib
  export
  two : Nat
  two = 2

pair : Vect Lib.two Int
pair = [1, 2]
