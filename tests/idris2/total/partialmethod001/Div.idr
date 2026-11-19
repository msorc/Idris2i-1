-- `div` and `mod` of the primitive integer types are partial (division by
-- zero), so a function using them is not covering, whether the
-- implementation is chosen here or passed in by a caller.
import Data.Nat

%default total

known : Int -> Int -> Int
known x y = x `div` y

knownMod : Bits8 -> Bits8 -> Bits8
knownMod x y = x `mod` y

knownInteger : Integer -> Integer
knownInteger x = div x 2

-- Total relative to the dictionary: the caller supplies it
abstract : Integral a => a -> a -> a
abstract x y = x `mod` y

viaAbstract : Int -> Int
viaAbstract x = abstract x 3

-- A guard does not help: the dictionary is partial
guarded : Int -> Int -> Int
guarded x y = if y == 0 then 0 else x `div` y

-- `Integral Nat` (from Data.Nat) is partial as well
nat : Nat -> Nat -> Nat
nat x y = x `div` y

-- This is fine: `Fractional Double` is total (dividing a Double by zero
-- gives an infinity or NaN)
double : Double -> Double
double x = x / 2

partial
honest : Int -> Int -> Int
honest x y = x `div` y

-- A covering function is not checked this way (without --method-totality)
covering
coveringOnly : Int -> Int -> Int
coveringOnly x y = x `div` y

-- Ranges of Int take `Integral Int`: the check is per implementation
range : Int -> List Int
range n = [0 .. n]

-- Asserting it, when the divisor is evidently not zero
asserted : Int -> Int
asserted x = assert_total $ x `div` 2
