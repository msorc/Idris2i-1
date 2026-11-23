module Rejection

-- A search rejects a candidate without unifying it with the goal when the
-- head of its type, or of one of its arguments, clashes with the goal. These
-- are the candidates that must still be found: an argument that is a data
-- constructor, a constant, `Type`, a function type, a type alias, a pair of
-- implementations in a local variable, a parent implementation.

interface Describe a where
  constructor MkDescribe
  describe : a -> String

Describe Int where
  describe _ = "Int"

Describe String where
  describe _ = "String"

Describe Bool where
  describe _ = "Bool"

Describe a => Describe (List a) where
  describe xs = "List " ++ concatMap describe xs

-- A hint whose type is an alias of the goal, which only evaluation shows
Alias : Type -> Type
Alias a = Describe a

%hint
describeChar : Alias Char
describeChar = MkDescribe (const "Char")

-- Data constructors in the goal
interface Size (n : Nat) where
  size : Nat

Size Z where
  size = 0

{n : Nat} -> Size n => Size (S n) where
  size = 1 + size {n}

-- Constants in the goal
interface Known (s : String) where
  known : String

Known "a" where
  known = "first"

Known "b" where
  known = "second"

-- Types in the goal
interface Univ (t : Type) where
  univ : String

Univ Type where
  univ = "Type"

Univ Int where
  univ = "Int"

Univ (Int -> Int) where
  univ = "Int -> Int"

-- A pair of implementations in a local variable
pairLocal : {auto p : (Describe a, Describe b)} -> a -> b -> String
pairLocal x y = describe x ++ " " ++ describe y

-- An implementation of a parent interface, from a local variable
eqFromOrd : Ord a => a -> a -> Bool
eqFromOrd x y = x == y

-- A local variable whose type is a function returning an implementation
fromFun : (Nat -> Describe a) -> a -> String
fromFun f x = describe @{f 0} x

-- Local variables of other types in scope, of which none can be used
manyLocals : Int -> String -> Bool -> List Int -> Nat -> String
manyLocals i s b xs n = describe i ++ describe s ++ describe b ++ describe xs

main : IO ()
main = do putStrLn (describe 'x')
          putStrLn (describe [True, False])
          printLn (size {n = 3})
          putStrLn (known {s = "b"})
          putStrLn (univ {t = Type})
          putStrLn (univ {t = Int -> Int})
          putStrLn (pairLocal (the Int 1) "two")
          printLn (eqFromOrd 'a' 'a')
          putStrLn (fromFun (const (MkDescribe (const "fun"))) ())
          putStrLn (manyLocals 1 "s" True [1] 2)
