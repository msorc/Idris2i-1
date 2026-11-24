-- A constraint that is postponed fails once a metavariable in it is solved
pick : {f : Nat -> Type} -> f 0 -> ((n : Nat) -> f n) -> ()
pick _ _ = ()

bad : ()
bad = pick (the Nat 3) (\n => "x")

-- Several constraints are left unsolved at the end of a definition
two : {f : Nat -> Type} -> f 0 -> f 1 -> ()
two _ _ = ()

leftover : ()
leftover = two (the Nat 3) (the String "y")
