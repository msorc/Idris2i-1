import Data.Nat.Solver

%default total

-- A mid-size goal: 20 monomials on each side, coefficients up to 6. Type
-- checking the proof computes both normal forms; the run script bounds the
-- time it takes, to catch a blow-up of the unary arithmetic.
cube : (x, y, z : Nat) ->
       (x + y + z + 1) * (x + y + z + 1) * (x + y + z + 1)
         = (x + (y + (z + 1))) * ((x + y) * (x + y + 2 * z + 2) + (z + 1) * (z + 1))
cube x y z = solveNat
