||| Data types, records, interfaces and implementations
module ApiFix.Shapes

%default total

public export
data Shape = Circle Double | Rect Double Double

||| An abstract type: its constructors are not API
export
data Token : Type where
  MkToken : Nat -> Token

public export
data Vec : Nat -> Type -> Type where
  Nil  : Vec Z a
  (::) : (x : a) -> (1 xs : Vec n a) -> Vec (S n) a

public export
record Point where
  constructor MkPoint
  x : Double
  0 tag : Nat
  y : Double

export
record Opaque where
  constructor MkOpaque
  secret : Nat

||| An interface with a parameter, a constraint and methods
public export
interface Show a => Pretty a where
  constructor MkPretty
  pretty : a -> String
  prettyList : List a -> String
  prettyList xs = concatMap pretty xs

public export
interface Convert (0 a : Type) b | a where
  convert : a -> b

export
Show Shape where
  show (Circle r) = "circle"
  show (Rect w h) = "rect"

export
Pretty Shape where
  pretty = show

||| A named implementation
export
[loud] Show Token where
  show (MkToken n) = "TOKEN"

export
Convert Shape Nat where
  convert (Circle _) = 1
  convert (Rect _ _) = 2

private
Show Opaque where
  show _ = "opaque"
