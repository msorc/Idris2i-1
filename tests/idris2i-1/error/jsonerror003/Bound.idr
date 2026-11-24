module Bound

-- A variable bound by the compiler, and a postponed constraint

swap : {a, b : Type} -> Either a b -> Either b a
swap {a = b} x = x

pick : {f : Nat -> Type} -> f 0 -> ((n : Nat) -> f n) -> ()
pick _ _ = ()

bad : ()
bad = pick (the Nat 3) (\n => "x")
