||| The run-time versions of the functions of Data.Nat (the `%transform`
||| rules to `Integer`) against copies of the reference definitions, over
||| ranges that include the boundaries (zero operands, too little fuel).
module Runtime

import Data.Nat
import Data.List

%default partial

-- Copies of the definitions of Data.Nat.  The rules do not apply to them
-- (they are other functions), so they run as they are written.
refLte : Nat -> Nat -> Bool
refLte Z        right     = True
refLte left     Z         = False
refLte (S left) (S right) = refLte left right

refMinimum : Nat -> Nat -> Nat
refMinimum Z m = Z
refMinimum (S n) Z = Z
refMinimum (S n) (S m) = S (refMinimum n m)

refMaximum : Nat -> Nat -> Nat
refMaximum Z m = m
refMaximum (S n) Z = S n
refMaximum (S n) (S m) = S (refMaximum n m)

refPower : Nat -> Nat -> Nat
refPower base Z       = S Z
refPower base (S exp) = base * (refPower base exp)

refMinus : Nat -> Nat -> Nat
refMinus Z        right     = Z
refMinus left     Z         = left
refMinus (S left) (S right) = refMinus left right

refMod' : Nat -> Nat -> Nat -> Nat
refMod' Z        centre right = centre
refMod' (S fuel) centre right =
      if refLte centre right then centre
         else refMod' fuel (refMinus centre (S right)) right

refDiv' : Nat -> Nat -> Nat -> Nat
refDiv' Z        centre right = Z
refDiv' (S fuel) centre right =
  if refLte centre right then Z
     else S (refDiv' fuel (refMinus centre (S right)) right)

refDivmod' : Nat -> Nat -> Nat -> (Nat, Nat)
refDivmod' Z        centre right = (Z, centre)
refDivmod' (S fuel) centre right =
  if refLte centre right then (Z, centre)
     else let qr = refDivmod' fuel (refMinus centre (S right)) right
          in (S (fst qr), snd qr)

refGcd : Nat -> Nat -> Nat
refGcd a Z = a
refGcd Z b = b
refGcd a (S b) = assert_total $ refGcd (S b) (refMod' a a b)

range : Nat -> List Nat
range n = [0 .. n]

check : Show a => Eq a => String -> List (a, a) -> IO ()
check name results
    = case filter (\(x, y) => x /= y) results of
           [] => putStrLn "\{name}: \{show (length results)} agree"
           ((x, y) :: _) => putStrLn "\{name}: MISMATCH \{show x} /= \{show y}"

pairs : Nat -> List (Nat, Nat)
pairs n = [(a, b) | a <- range n, b <- range n]

triples : Nat -> List (Nat, Nat, Nat)
triples n = [(f, c, r) | f <- range n, c <- range n, r <- range n]

main : IO ()
main = do
  check "lte" [(lte a b, refLte a b) | (a, b) <- pairs 20]
  check "gte" [(gte a b, refLte b a) | (a, b) <- pairs 20]
  check "lt" [(lt a b, refLte (S a) b) | (a, b) <- pairs 20]
  check "gt" [(gt a b, refLte (S b) a) | (a, b) <- pairs 20]
  check "minimum" [(minimum a b, refMinimum a b) | (a, b) <- pairs 20]
  check "maximum" [(maximum a b, refMaximum a b) | (a, b) <- pairs 20]
  check "power" [(power a b, refPower a b) | (a, b) <- pairs 12]
  check "mod'" [(mod' f c r, refMod' f c r) | (f, c, r) <- triples 12]
  check "div'" [(div' f c r, refDiv' f c r) | (f, c, r) <- triples 12]
  check "divmod'" [(divmod' f c r, refDivmod' f c r) | (f, c, r) <- triples 12]
  check "divNatNZ" [(divNatNZ a (S b) ItIsSucc, refDiv' a a b) | (a, b) <- pairs 30]
  check "modNatNZ" [(modNatNZ a (S b) ItIsSucc, refMod' a a b) | (a, b) <- pairs 30]
  check "divmodNatNZ" [(divmodNatNZ a (S b) ItIsSucc, refDivmod' a a b) | (a, b) <- pairs 30]
  check "div" [(a `div` S b, refDiv' a a b) | (a, b) <- pairs 30]
  check "mod" [(a `mod` S b, refMod' a a b) | (a, b) <- pairs 30]
  check "gcd" [(gcd (S a) b, refGcd (S a) b) | (a, b) <- pairs 30]
  check "lcm" [(lcm a b, if a == 0 || b == 0 then 0 else (a * b) `div` refGcd a b) | (a, b) <- pairs 30]
  -- large operands: beyond 32 bits, where the RefC Integers are boxed
  let big = the Nat 123456789012345678901234567890
  printLn (lte big (big + 1), lte (big + 1) big, minimum big 7, maximum big 7)
  printLn (power 3 100, power 0 0, power 0 5, power big 2 == big * big)
  printLn (big `div` 1000000007, big `mod` 1000000007, gcd {ok = LeftIsNotZero} (S big) 1234567890)
  printLn (divmod' 3 big 9, div' 5 100 9, mod' 5 100 9)

-- The public definitions still reduce as before at type-checking time.
power210 : power 2 10 = 1024
power210 = Refl

lte35 : lte 3 5 = True
lte35 = Refl

div72 : divNatNZ 7 2 ItIsSucc = 3
div72 = Refl

mod72 : modNatNZ 7 2 ItIsSucc = 1
mod72 = Refl

min35 : minimum 3 5 = 3
min35 = Refl
