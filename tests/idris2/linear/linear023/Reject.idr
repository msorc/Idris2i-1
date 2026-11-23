||| (Experimental) What quantity variables must reject
module Reject

%default total

data LList : Type -> Type where
  Nil  : LList a
  (::) : (1 x : a) -> (1 xs : LList a) -> LList a

pid : (%q x : a) -> a
pid x = x

-- A %q-bound variable is used exactly once (%q may be 1) ...
failing "There are 2 uses of linear name x"
  dup : (%q x : a) -> LPair a a
  dup x = x # x

-- ... it can't be dropped ...
failing "There are 0 uses of linear name x"
  drop : (%q x : a) -> ()
  drop x = ()

-- ... nor given to an unrestricted argument (%q may be 1)
failing "Trying to use %q name x in non-linear context"
  toOmega : (%q x : a) -> (a -> b) -> b
  toOmega x f = f x

-- A 1-bound variable can't be given to a %q argument (%q may be omega)
failing "Trying to use linear name y in %q context"
  fromOne : (%q x : a) -> (1 y : a) -> LPair a a
  fromOne x y = x # idq y
    where
      idq : (%q z : a) -> a
      idq z = z

-- Two variables are not the same
failing "Trying to use %q name x in %r context"
  confuse : (%q x : a) -> (%r y : a) -> LPair a a
  confuse x y = useR x # y
    where
      useR : (%r z : a) -> a
      useR z = z

-- A quantity variable is never chosen to be 0
failing "Mismatch between: ?a -> ?a and (0 _ : Nat) -> Nat"
  atZero : (0 _ : Nat) -> Nat
  atZero = pid

-- Written unrestricted, a linear argument can't be given
failing "Trying to use linear name x in non-linear context"
  applied : (1 x : a) -> a
  applied x = pid {%q = omega} x

-- The variables of a definition, when it is unfolded in a type, stay its
-- own: rigid, and not those of the definition that uses it
PolyT : ((%q _ : Nat) -> Nat) -> Type
PolyT _ = (%q y : Nat) -> Nat

ok : PolyT (\y => y)
ok = \y => y

failing "Trying to use %q name y in non-linear context"
  stale : PolyT (\y => y)
  stale = \y => y + y

failing "Mismatch between: (%q _ : Nat) -> Nat and Nat -> Nat"
  staleOmega : PolyT (\y => y) -> Nat -> Nat
  staleOmega f = f

failing "Trying to use %q (of Reject.staleNext) name x in %q (of Reject.PolyT) context"
  staleNext : (%q x : Nat) -> PolyT (\y => y) -> Nat
  staleNext x f = f x

-- Only in the type signature of a function, and its clauses
failing "The quantity variable %q is not bound here"
  data Bad : Type where
    MkBad : (%q x : Nat) -> Bad

failing "The quantity variable %r is not bound here"
  unbound : (%q x : Nat) -> Nat
  unbound x = (\ %r y => y) x
