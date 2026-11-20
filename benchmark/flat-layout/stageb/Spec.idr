module Spec

interface Rd (arr : Type -> Type) where
  rd : arr t -> Int -> Maybe t

data A : Type -> Type where
  MkA : List t -> A t

Rd A where
  %spec t
  rd (MkA xs) i = if i < 0 then Nothing else go xs i
    where
      go : List t -> Int -> Maybe t
      go [] _ = Nothing
      go (x :: _) 0 = Just x
      go (_ :: r) k = go r (k - 1)

main : IO ()
main = printLn (rd (MkA [1.0, 2.0]) 1)
