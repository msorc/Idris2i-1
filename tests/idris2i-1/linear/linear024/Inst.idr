||| (Experimental) Quantity variables chosen at applied references: from
||| the expected type of the application, then from the explicit arguments
||| that tell without being elaborated, else omega; or written,
||| `f {%q = 1}`.
module Inst

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

pmap : ((%q _ : a) -> b) -> (%q xs : LList a) -> LList b
pmap f [] = []
pmap f (x :: xs) = f x :: pmap f xs

pid : (%q x : a) -> a
pid x = x

pcompose : ((%q _ : b) -> c) -> ((%q _ : a) -> b) -> (%q _ : a) -> c
pcompose f g x = f (g x)

lreverse : (1 acc : LList a) -> (1 xs : LList a) -> LList a
lreverse acc [] = acc
lreverse acc (x :: xs) = lreverse (x :: acc) xs

------------------------------------------------------------------------------
-- At 1

-- from the quantity a local variable given is bound at (and from the type
-- of `value`)
values : (1 ts : LList Token) -> LList Nat
values ts = pmap value ts

-- from the type of a global given as an argument
valuesOf : (1 ts : LList Token) -> LList Nat
valuesOf ts = pmap value (lreverse [] ts)

-- from a lambda whose binder has a written quantity
copyAll : (1 ts : LList Nat) -> LList Nat
copyAll ts = pmap (\1 x => x) ts

-- from the expected type of the application
twiceLin : ((1 _ : a) -> a) -> (1 _ : a) -> a
twiceLin f = pcompose f f

-- written
valuesW : (1 ts : LList Token) -> LList Nat
valuesW ts = pmap {%q = 1} (\t => value t) (lreverse [] ts)

-- a reference given as an argument takes the quantity from what it is
-- given to
same : (%r xs : LList a) -> LList a
same xs = pmap pid xs

------------------------------------------------------------------------------
-- At omega

doubles : LList Nat -> LList Nat
doubles xs = pmap (\x => x + x) xs

succs : LList Nat -> LList Nat
succs xs = pmap {%q = omega} S xs

twice : (Nat, Nat)
twice = let n = pid 3 in (n, n)

------------------------------------------------------------------------------
-- A local function with a quantity variable of its own

useLocal : (1 t : Token) -> Nat -> LPair Nat Nat
useLocal t n = value (lid t) # (lid n + lid n)
  where
    lid : (%s x : a) -> a
    lid x = x

------------------------------------------------------------------------------

ltoList : LList a -> List a
ltoList [] = []
ltoList (x :: xs) = x :: ltoList xs

tokens : Nat -> LList Token
tokens Z = []
tokens (S k) = MkToken (S k) :: tokens k

export
main : IO ()
main = do printLn (ltoList (values (tokens 3)))
          printLn (ltoList (valuesOf (tokens 3)))
          printLn (ltoList (valuesW (tokens 2)))
          printLn (ltoList (copyAll [1, 2]))
          printLn (twiceLin (\1 x => x) 'a')
          printLn (ltoList (same [4, 5]))
          printLn (ltoList (doubles [1, 2]), ltoList (succs [1, 2]), twice)
          case useLocal (MkToken 7) 2 of
               (a # b) => printLn (a, b)
