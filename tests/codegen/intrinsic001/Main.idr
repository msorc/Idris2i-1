||| The constructors of a list or option shaped type (or of a record of two
||| fields) are compiled to the intrinsic constructors `_builtin.CONS`, ...,
||| unless one of them has a field that a back end may store raw (a Double,
||| an Int, an Int64 or a Bits64): then they keep their names, and a
||| conversion between such a type and `List`, `Maybe` or a pair is not the
||| identity.
module Main

-- Keep their names: a Double, an Int, a Bits64 field.
data DL = DNil | DCons Double DL

record V2 where
  constructor MkV2
  x : Double
  y : Double

data MI = NoI | SomeI Int

data BL = BNil | BCons Bits64 BL

-- Intrinsic as before: Char and Bits8 are immediate values anyway, and a
-- polymorphic field is boxed.
data CL = CNil | CCons Char CL

data Opt a = None | Some a

toD : List Double -> DL
toD [] = DNil
toD (x :: xs) = DCons x (toD xs)

sumD : DL -> Double
sumD DNil = 0
sumD (DCons x r) = x + sumD r

toV2 : (Double, Double) -> V2
toV2 (a, b) = MkV2 a b

toMI : Maybe Int -> MI
toMI Nothing = NoI
toMI (Just i) = SomeI i

toBL : List Bits64 -> BL
toBL [] = BNil
toBL (x :: xs) = BCons x (toBL xs)

lenBL : BL -> Nat
lenBL BNil = 0
lenBL (BCons _ r) = S (lenBL r)

toC : List Char -> CL
toC [] = CNil
toC (c :: cs) = CCons c (toC cs)

lenC : CL -> Nat
lenC CNil = 0
lenC (CCons _ r) = S (lenC r)

toOpt : Maybe a -> Opt a
toOpt Nothing = None
toOpt (Just a) = Some a

main : IO ()
main = do
  printLn (sumD (toD [1.0, 2.0]))
  let v = toV2 (3.0, 4.0)
  printLn (v.x + v.y)
  printLn (case toMI (Just 5) of NoI => 0; SomeI i => i)
  printLn (lenBL (toBL [1, 2, 3]), lenC (toC ['a', 'b']))
  printLn (case toOpt (Just "s") of None => ""; Some s => s)
