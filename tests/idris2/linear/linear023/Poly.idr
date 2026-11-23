||| (Experimental) Quantity variables: `%q` in a type signature ranges over
||| 1 and omega.  A reference to the function chooses the quantity from the
||| expected type when it is a known function type (else omega).
module Poly

%default total

public export
data LList : Type -> Type where
  Nil  : LList a
  (::) : (1 x : a) -> (1 xs : LList a) -> LList a

export
data Token : Type where
  MkToken : Nat -> Token

value : (1 _ : Token) -> Nat
value (MkToken n) = n

------------------------------------------------------------------------------
-- Written once

pid : (%q x : a) -> a
pid x = x

pcompose : ((%q _ : b) -> c) -> ((%q _ : a) -> b) -> (%q _ : a) -> c
pcompose f g x = f (g x)

pmap : ((%q _ : a) -> b) -> (%q xs : LList a) -> LList b
pmap f [] = []
pmap f (x :: xs) = f x :: pmap f xs

-- A lambda in the clauses can use the signature's variable
pid' : (%q x : a) -> a
pid' = \ %q y => y

-- Two variables
both : ((%q _ : a) -> c) -> ((%r _ : b) -> d) ->
       (%q x : a) -> (%r y : b) -> LPair c d
both f g x y = f x # g y

-- A case in a polymorphic function: the scrutinee is checked at %q
swap : (%q p : LPair a b) -> LPair b a
swap p = case p of
              (x # y) => y # x

------------------------------------------------------------------------------
-- At 1

idLin : (1 x : a) -> a
idLin = pid

composeLin : ((1 _ : b) -> c) -> ((1 _ : a) -> b) -> (1 _ : a) -> c
composeLin = pcompose

mapLin : ((1 _ : a) -> b) -> (1 xs : LList a) -> LList b
mapLin = pmap

values : (1 ts : LList Token) -> LList Nat
values ts = mapLin value ts

bothLin : (1 t : Token) -> Nat -> LPair Nat Nat
bothLin t n = (the (((1 _ : Token) -> Nat) -> (Nat -> Nat) ->
                    (1 _ : Token) -> Nat -> LPair Nat Nat) both) value S t n

------------------------------------------------------------------------------
-- At omega (chosen from the expected type, or by default when applied)

idW : a -> a
idW = pid

idW' : a -> a
idW' = pid'

twice : Nat -> (Nat, Nat)
twice n = let m = pid n in (m, m)

mapW : (a -> b) -> LList a -> LList b
mapW = pmap

doubles : LList Nat -> LList Nat
doubles xs = pmap (\x => x + x) xs

plusTwo : Nat -> Nat
plusTwo = pcompose S S

------------------------------------------------------------------------------

ltoList : LList a -> List a
ltoList [] = []
ltoList (x :: xs) = x :: ltoList xs

tokens : LList Token
tokens = mapW MkToken [1, 2, 3]

export
main : IO ()
main = do printLn (ltoList (values tokens))
          printLn (ltoList (doubles [1, 2, 3]))
          printLn (twice 4, plusTwo 1, idW 'c')
          case bothLin (MkToken 7) 1 of
               (a # b) => printLn (a, b)
          case swap (the (LPair Nat Nat) (5 # 6)) of
               (a # b) => printLn (a, b)
