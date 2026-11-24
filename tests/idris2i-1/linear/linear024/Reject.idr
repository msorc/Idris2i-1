||| (Experimental) Where the choice at an applied reference is wrong or
||| can't be made, and the errors
module Reject

%default total

data LList : Type -> Type where
  Nil  : LList a
  (::) : (1 x : a) -> (1 xs : LList a) -> LList a

data Token : Type where
  MkToken : Nat -> Token

value : (1 _ : Token) -> Nat
value (MkToken n) = n

pmap : ((%q _ : a) -> b) -> (%q xs : LList a) -> LList b
pmap f [] = []
pmap f (x :: xs) = f x :: pmap f xs

lreverse : (1 acc : LList a) -> (1 xs : LList a) -> LList a
lreverse acc [] = acc
lreverse acc (x :: xs) = lreverse (x :: acc) xs

-- Nothing tells: the list is an application and the lambda has no written
-- quantity, so %q is unrestricted, and the linear `ts` can't be used
failing "The quantities of pmap were chosen as %q = unrestricted (by default)"
  noInfo : (1 ts : LList Token) -> LList Nat
  noInfo ts = pmap (\t => value t) (lreverse [] ts)

-- The first that tells wins: `ts` says 1, and the lambda uses its argument
-- twice
failing "The quantities of pmap were chosen as %q = 1 (because ts is bound at that quantity)"
  twiceEach : (1 ts : LList Nat) -> LList Nat
  twiceEach ts = pmap (\x => x + x) ts

-- What can't be written
failing "A quantity variable can't be 0"
  zero : LList Nat -> LList Nat
  zero xs = pmap {%q = 0} S xs

failing "Reject.pmap has no quantity variable %r"
  other : LList Nat -> LList Nat
  other xs = pmap {%r = 1} S xs

failing "Only a function with quantity variables can be given quantities"
  notPoly : (1 ts : LList Token) -> LList Token
  notPoly ts = lreverse {%q = 1} [] ts

failing "The quantity variable %r is not bound here"
  unbound : LList Nat -> LList Nat
  unbound xs = pmap {%q = %r} S xs

failing "can't be written here"
  own : ((%q _ : a) -> b) -> (%q xs : LList a) -> LList b
  own f [] = []
  own f (x :: xs) = f x :: own {%q = 1} f xs
