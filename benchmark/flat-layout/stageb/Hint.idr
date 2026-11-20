module Hint

-- A stand-in for the descriptor of stage B.
export
data Layout : Type -> Type where
  LBoxed : Layout a
  LDouble : Layout Double
  LMaybe : Layout a -> Layout (Maybe a)

export
describe : Layout a -> String
describe LBoxed = "boxed"
describe LDouble = "double"
describe (LMaybe l) = "maybe " ++ describe l

%defaulthint
export
boxedLayout : Layout a
boxedLayout = LBoxed

%hint
export
layoutDouble : Layout Double
layoutDouble = LDouble

%hint
export
layoutMaybe : Layout a => Layout (Maybe a)
layoutMaybe @{l} = LMaybe l

-- An "array" that records the layout it was made with.
public export
record Arr t where
  constructor MkArr
  layoutName : String
  elems : List t
