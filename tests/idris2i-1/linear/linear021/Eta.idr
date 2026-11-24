||| A function with linear arguments can be used where a function with
||| unrestricted arguments is expected: it is eta-expanded (`\x => f x`).
||| Only 1 becomes omega, only along the result of the expected function type,
||| and only where that type is a known function type.
module Eta

%default total

data LList : Type -> Type where
  Nil  : LList a
  (::) : (1 x : a) -> (1 xs : LList a) -> LList a

lid : (1 x : a) -> a
lid x = x

lcons : (1 x : a) -> (1 xs : LList a) -> LList a
lcons = (::)

mapL : (a -> b) -> List a -> List b
mapL f [] = []
mapL f (x :: xs) = f x :: mapL f xs

zipW : (a -> b -> c) -> List a -> List b -> List c
zipW f (x :: xs) (y :: ys) = f x y :: zipW f xs ys
zipW _ _ _ = []

-- A global function
t1 : List Nat
t1 = mapL lid [1, 2]

-- A partially applied constructor, one and two arguments expanded
t2 : List (LList Nat -> LList Nat)
t2 = mapL (::) [1, 2]

t3 : List (LList Nat)
t3 = zipW (::) [1, 2] [[], [3]]

t4 : List Nat -> LList Nat
t4 = foldr (::) []

-- Only the second argument is linear
second : Nat -> (1 _ : LList Nat) -> LList Nat
second x xs = x :: xs

t5 : List (LList Nat)
t5 = zipW second [1, 2] [[], [3]]

-- A local variable
t6 : ((1 _ : Nat) -> Nat) -> List Nat
t6 f = mapL f [1, 2]

-- A linear function used once in a linear position: the expansion uses it
-- once
once : (1 g : Nat -> Nat) -> Nat
once g = g 0

t7 : (1 f : (1 _ : Nat) -> Nat) -> Nat
t7 f = once f

-- A function type reached by reduction
Endo : Type -> Type
Endo a = a -> a

t9 : Endo Nat
t9 = lid

-- A linear function bound in a let, and through `the`
t10 : List Nat
t10 = let f : (1 _ : Nat) -> Nat
          f x = x in
          mapL f [1, 2]

t11 : Nat -> Nat
t11 = the (Nat -> Nat) lid

-- A linear-bound function can't go to an unrestricted argument
failing "Trying to use linear name f in non-linear context"
  t12 : (1 f : (1 _ : Nat) -> Nat) -> List Nat
  t12 f = mapL f [1, 2]

-- The unsound direction stays an error
failing "Mismatch between: Nat -> Nat and (1 _ : Nat) -> Nat"
  t13 : (Nat -> Nat) -> (1 _ : Nat) -> Nat
  t13 f = f

-- Erased arguments are never coerced, either way
failing "Mismatch between: (0 _ : Nat) -> Nat and Nat -> Nat"
  t14 : ((0 _ : Nat) -> Nat) -> Nat -> Nat
  t14 f = f

failing "Mismatch between: Nat -> Nat and (0 _ : Nat) -> Nat"
  t15 : (Nat -> Nat) -> (0 _ : Nat) -> Nat
  t15 f = f

-- Not inside the argument of the expected function type (contravariant: it
-- would need omega to become 1 there)
failing "Mismatch between: (1 _ : Nat) -> Nat and Nat -> Nat"
  t16 : (((1 _ : Nat) -> Nat) -> Nat) -> (Nat -> Nat) -> Nat
  t16 f = f

-- Nor inside a data type
failing "Mismatch between: (1 _ : Nat) -> Nat and Nat -> Nat"
  t17 : List ((1 _ : Nat) -> Nat) -> List (Nat -> Nat)
  t17 xs = xs

-- Nor in a type
P : (Nat -> Nat) -> Type
P _ = Nat

failing "Mismatch between: (1 _ : Nat) -> Nat and Nat -> Nat"
  t18 : (f : (1 _ : Nat) -> Nat) -> P f
  t18 f = 0

-- Nor where the expected type is not known to be a function type yet, as
-- for the result of `map` from `Functor`, whose type is only known after its
-- argument has been checked
failing "Mismatch between: (1 _ : LList Nat) -> LList Nat and LList Nat -> LList Nat"
  t19 : List Nat -> List (LList Nat -> LList Nat)
  t19 xs = map lcons xs

-- ... which giving the type of the function's result fixes
t19b : List Nat -> List (LList Nat -> LList Nat)
t19b xs = map {b = LList Nat -> LList Nat} lcons xs

-- A name is not made ambiguous by the coercion: the alternative that needs
-- no coercion wins
namespace L
  export
  id : (1 x : a) -> a
  id x = x

t20 : List Nat
t20 = mapL id [1, 2]

-- ... but one that works only with the coercion is still found
namespace M
  export
  only : (1 x : Nat) -> Nat
  only x = x

namespace N
  export
  only : Bool -> Bool
  only x = x

t21 : List Nat
t21 = mapL only [1, 2]
