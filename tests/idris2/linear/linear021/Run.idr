module Main

import Data.List

data LList : Type -> Type where
  Nil  : LList a
  (::) : (1 x : a) -> (1 xs : LList a) -> LList a

lToList : LList a -> List a
lToList [] = []
lToList (x :: xs) = x :: lToList xs

lid : (1 x : a) -> a
lid x = x

g : (1 _ : Nat) -> (1 _ : LList Nat) -> LList Nat
g x y = x :: y

main : IO ()
main = do printLn (map lid (the (List Nat) [1, 2, 3]))
          printLn (map lToList (zipWith (::) [1, 2] (the (List (LList Nat)) [[], [3]])))
          printLn (map lToList (zipWith g [1, 2] (the (List (LList Nat)) [[10], [20]])))
          printLn (lToList (foldr g [] (the (List Nat) [1, 2, 3])))
          printLn (lToList (foldl (flip g) [] (the (List Nat) [1, 2, 3])))
