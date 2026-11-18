module B

-- B re-exports A, so A is imported twice by C (directly, as X, and through B)
import public A

public export
h : Nat
h = f (MkT 2) +++ g
