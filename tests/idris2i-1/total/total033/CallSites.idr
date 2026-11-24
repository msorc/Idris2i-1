%default total

-- Direct recursion that doesn't decrease: the call site should be reported
loop : Nat -> Nat
loop n = loop (S n)

-- Mutual recursion: each call on the path should be reported
mutual
  ping : Nat -> Bool
  ping n = pong (S n)

  pong : Nat -> Bool
  pong n = ping n

-- Calling a non-terminating function via an intermediate one
spin : Nat -> Nat
spin n = spin n

viaHelper : Nat -> Nat
viaHelper n = helper n
  where
    helper : Nat -> Nat
    helper m = spin m
