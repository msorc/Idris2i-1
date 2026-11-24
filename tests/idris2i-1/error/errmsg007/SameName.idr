-- Two different variables called b: the one the user named keeps its name,
-- the one bound by the compiler is numbered
swap : {a, b : Type} -> Either a b -> Either b a
swap {a = b} x = x

-- Variables with different names print as before
test : {x : Nat} -> (p : Nat -> Type) -> p x -> (y : Nat) -> p y
test p px y = px
