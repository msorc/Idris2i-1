data Colour = Red | Orange | Yellow | Green | Blue | Indigo | Violet
            | Black | White | Grey | Brown | Pink | Cyan

-- Many missing cases: the list is cut short
isRed : Colour -> Bool
isRed Red = True

data Same : Nat -> Nat -> Type where
  MkSame : (n : Nat) -> Same n n

-- A variable that occurs twice in a missing case keeps a name
same : (m, n : Nat) -> Same m n -> Bool
same Z Z (MkSame Z) = True

-- Variables that occur once are printed as `_`
pairs : List (Nat, Nat) -> Nat
pairs [] = 0

partial
part : Nat -> Nat
part Z = Z

-- A call to a function that is not covering
callsPart : Nat -> Nat
callsPart n = 1 + part n
