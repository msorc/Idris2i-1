-- Different unsolved metavariables that would all print as ?_ are numbered
-- in the message
pick : Maybe Nat -> Nat
pick m = case the (Either _ _) m of
              Left n => n
              Right n => n

-- A single one is printed as before
one : Maybe Nat -> Nat
one m = case the (List _) m of
             _ => 0
