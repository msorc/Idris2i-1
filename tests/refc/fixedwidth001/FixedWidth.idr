-- Generated (see the comment of main): arithmetic, shifts, casts and `case`s
-- of the fixed width types, compared with the Chez backend.
module Main

import Data.List
import Data.String
import System

%default covering

-- The values of the tests are made at run time (from the number of
-- arguments of the program), so that the compiler does not fold them.

data Val = VB8 Bits8 | VB16 Bits16 | VB32 Bits32 | VB64 Bits64 | VI8 Int8 | VI16 Int16 | VI32 Int32 | VI64 Int64 | VI Int | VBI Integer

data Ty = TB8 | TB16 | TB32 | TB64 | TI8 | TI16 | TI32 | TI64 | TI | TBI

allTys : List Ty
allTys = [TB8, TB16, TB32, TB64, TI8, TI16, TI32, TI64, TI, TBI]

-- A value with a mark: `*` when a `case` on literals found it, `#x` when the
-- `case` took the branch of another literal x (a bug).
mark : String -> String -> String
mark s c = if c == "_" then s else if c == s then s ++ "*" else s ++ "#" ++ c

caseB8 : Bits8 -> String
caseB8 x = case x of
  0 => "0"
  1 => "1"
  2 => "2"
  3 => "3"
  55 => "55"
  56 => "56"
  100 => "100"
  127 => "127"
  128 => "128"
  144 => "144"
  200 => "200"
  254 => "254"
  255 => "255"
  _ => "_"

caseB16 : Bits16 -> String
caseB16 x = case x of
  0 => "0"
  1 => "1"
  2 => "2"
  3 => "3"
  55 => "55"
  56 => "56"
  100 => "100"
  127 => "127"
  128 => "128"
  144 => "144"
  200 => "200"
  254 => "254"
  255 => "255"
  256 => "256"
  400 => "400"
  32767 => "32767"
  32768 => "32768"
  65535 => "65535"
  _ => "_"

caseB32 : Bits32 -> String
caseB32 x = case x of
  0 => "0"
  1 => "1"
  2 => "2"
  3 => "3"
  55 => "55"
  56 => "56"
  100 => "100"
  127 => "127"
  128 => "128"
  144 => "144"
  200 => "200"
  254 => "254"
  255 => "255"
  256 => "256"
  400 => "400"
  32767 => "32767"
  32768 => "32768"
  65535 => "65535"
  65536 => "65536"
  2147483647 => "2147483647"
  2147483648 => "2147483648"
  4294967295 => "4294967295"
  _ => "_"

caseB64 : Bits64 -> String
caseB64 x = case x of
  0 => "0"
  1 => "1"
  2 => "2"
  3 => "3"
  55 => "55"
  56 => "56"
  100 => "100"
  127 => "127"
  128 => "128"
  144 => "144"
  200 => "200"
  254 => "254"
  255 => "255"
  256 => "256"
  400 => "400"
  32767 => "32767"
  32768 => "32768"
  65535 => "65535"
  65536 => "65536"
  2147483647 => "2147483647"
  2147483648 => "2147483648"
  4294967295 => "4294967295"
  4294967296 => "4294967296"
  9223372036854775807 => "9223372036854775807"
  9223372036854775808 => "9223372036854775808"
  18446744073709551615 => "18446744073709551615"
  _ => "_"

caseI8 : Int8 -> String
caseI8 x = case x of
  (-128) => "-128"
  (-127) => "-127"
  (-112) => "-112"
  (-100) => "-100"
  (-56) => "-56"
  (-2) => "-2"
  (-1) => "-1"
  0 => "0"
  1 => "1"
  2 => "2"
  3 => "3"
  55 => "55"
  56 => "56"
  100 => "100"
  127 => "127"
  _ => "_"

caseI16 : Int16 -> String
caseI16 x = case x of
  (-32768) => "-32768"
  (-129) => "-129"
  (-128) => "-128"
  (-127) => "-127"
  (-112) => "-112"
  (-100) => "-100"
  (-56) => "-56"
  (-2) => "-2"
  (-1) => "-1"
  0 => "0"
  1 => "1"
  2 => "2"
  3 => "3"
  55 => "55"
  56 => "56"
  100 => "100"
  127 => "127"
  128 => "128"
  144 => "144"
  200 => "200"
  254 => "254"
  255 => "255"
  256 => "256"
  400 => "400"
  32767 => "32767"
  _ => "_"

caseI32 : Int32 -> String
caseI32 x = case x of
  (-2147483648) => "-2147483648"
  (-32769) => "-32769"
  (-32768) => "-32768"
  (-129) => "-129"
  (-128) => "-128"
  (-127) => "-127"
  (-112) => "-112"
  (-100) => "-100"
  (-56) => "-56"
  (-2) => "-2"
  (-1) => "-1"
  0 => "0"
  1 => "1"
  2 => "2"
  3 => "3"
  55 => "55"
  56 => "56"
  100 => "100"
  127 => "127"
  128 => "128"
  144 => "144"
  200 => "200"
  254 => "254"
  255 => "255"
  256 => "256"
  400 => "400"
  32767 => "32767"
  32768 => "32768"
  65535 => "65535"
  65536 => "65536"
  2147483647 => "2147483647"
  _ => "_"

caseI64 : Int64 -> String
caseI64 x = case x of
  (-9223372036854775808) => "-9223372036854775808"
  (-2147483649) => "-2147483649"
  (-2147483648) => "-2147483648"
  (-32769) => "-32769"
  (-32768) => "-32768"
  (-129) => "-129"
  (-128) => "-128"
  (-127) => "-127"
  (-112) => "-112"
  (-100) => "-100"
  (-56) => "-56"
  (-2) => "-2"
  (-1) => "-1"
  0 => "0"
  1 => "1"
  2 => "2"
  3 => "3"
  55 => "55"
  56 => "56"
  100 => "100"
  127 => "127"
  128 => "128"
  144 => "144"
  200 => "200"
  254 => "254"
  255 => "255"
  256 => "256"
  400 => "400"
  32767 => "32767"
  32768 => "32768"
  65535 => "65535"
  65536 => "65536"
  2147483647 => "2147483647"
  2147483648 => "2147483648"
  4294967295 => "4294967295"
  4294967296 => "4294967296"
  9223372036854775807 => "9223372036854775807"
  _ => "_"

caseI : Int -> String
caseI x = case x of
  (-9223372036854775808) => "-9223372036854775808"
  (-2147483649) => "-2147483649"
  (-2147483648) => "-2147483648"
  (-32769) => "-32769"
  (-32768) => "-32768"
  (-129) => "-129"
  (-128) => "-128"
  (-127) => "-127"
  (-112) => "-112"
  (-100) => "-100"
  (-56) => "-56"
  (-2) => "-2"
  (-1) => "-1"
  0 => "0"
  1 => "1"
  2 => "2"
  3 => "3"
  55 => "55"
  56 => "56"
  100 => "100"
  127 => "127"
  128 => "128"
  144 => "144"
  200 => "200"
  254 => "254"
  255 => "255"
  256 => "256"
  400 => "400"
  32767 => "32767"
  32768 => "32768"
  65535 => "65535"
  65536 => "65536"
  2147483647 => "2147483647"
  2147483648 => "2147483648"
  4294967295 => "4294967295"
  4294967296 => "4294967296"
  9223372036854775807 => "9223372036854775807"
  _ => "_"

caseBI : Integer -> String
caseBI x = case x of
  (-9223372036854775808) => "-9223372036854775808"
  (-2147483649) => "-2147483649"
  (-2147483648) => "-2147483648"
  (-32769) => "-32769"
  (-32768) => "-32768"
  (-129) => "-129"
  (-128) => "-128"
  (-127) => "-127"
  (-112) => "-112"
  (-100) => "-100"
  (-56) => "-56"
  (-2) => "-2"
  (-1) => "-1"
  0 => "0"
  1 => "1"
  2 => "2"
  3 => "3"
  55 => "55"
  56 => "56"
  100 => "100"
  127 => "127"
  128 => "128"
  144 => "144"
  200 => "200"
  254 => "254"
  255 => "255"
  256 => "256"
  400 => "400"
  32767 => "32767"
  32768 => "32768"
  65535 => "65535"
  65536 => "65536"
  2147483647 => "2147483647"
  2147483648 => "2147483648"
  4294967295 => "4294967295"
  4294967296 => "4294967296"
  9223372036854775807 => "9223372036854775807"
  9223372036854775808 => "9223372036854775808"
  18446744073709551615 => "18446744073709551615"
  _ => "_"

showVal : Val -> String
showVal (VB8 x) = mark (show x) (caseB8 x)
showVal (VB16 x) = mark (show x) (caseB16 x)
showVal (VB32 x) = mark (show x) (caseB32 x)
showVal (VB64 x) = mark (show x) (caseB64 x)
showVal (VI8 x) = mark (show x) (caseI8 x)
showVal (VI16 x) = mark (show x) (caseI16 x)
showVal (VI32 x) = mark (show x) (caseI32 x)
showVal (VI64 x) = mark (show x) (caseI64 x)
showVal (VI x) = mark (show x) (caseI x)
showVal (VBI x) = mark (show x) (caseBI x)

conv : Ty -> Val -> Val
conv TB8 (VB8 x) = VB8 x
conv TB16 (VB8 x) = VB16 (cast x)
conv TB32 (VB8 x) = VB32 (cast x)
conv TB64 (VB8 x) = VB64 (cast x)
conv TI8 (VB8 x) = VI8 (cast x)
conv TI16 (VB8 x) = VI16 (cast x)
conv TI32 (VB8 x) = VI32 (cast x)
conv TI64 (VB8 x) = VI64 (cast x)
conv TI (VB8 x) = VI (cast x)
conv TBI (VB8 x) = VBI (cast x)
conv TB8 (VB16 x) = VB8 (cast x)
conv TB16 (VB16 x) = VB16 x
conv TB32 (VB16 x) = VB32 (cast x)
conv TB64 (VB16 x) = VB64 (cast x)
conv TI8 (VB16 x) = VI8 (cast x)
conv TI16 (VB16 x) = VI16 (cast x)
conv TI32 (VB16 x) = VI32 (cast x)
conv TI64 (VB16 x) = VI64 (cast x)
conv TI (VB16 x) = VI (cast x)
conv TBI (VB16 x) = VBI (cast x)
conv TB8 (VB32 x) = VB8 (cast x)
conv TB16 (VB32 x) = VB16 (cast x)
conv TB32 (VB32 x) = VB32 x
conv TB64 (VB32 x) = VB64 (cast x)
conv TI8 (VB32 x) = VI8 (cast x)
conv TI16 (VB32 x) = VI16 (cast x)
conv TI32 (VB32 x) = VI32 (cast x)
conv TI64 (VB32 x) = VI64 (cast x)
conv TI (VB32 x) = VI (cast x)
conv TBI (VB32 x) = VBI (cast x)
conv TB8 (VB64 x) = VB8 (cast x)
conv TB16 (VB64 x) = VB16 (cast x)
conv TB32 (VB64 x) = VB32 (cast x)
conv TB64 (VB64 x) = VB64 x
conv TI8 (VB64 x) = VI8 (cast x)
conv TI16 (VB64 x) = VI16 (cast x)
conv TI32 (VB64 x) = VI32 (cast x)
conv TI64 (VB64 x) = VI64 (cast x)
conv TI (VB64 x) = VI (cast x)
conv TBI (VB64 x) = VBI (cast x)
conv TB8 (VI8 x) = VB8 (cast x)
conv TB16 (VI8 x) = VB16 (cast x)
conv TB32 (VI8 x) = VB32 (cast x)
conv TB64 (VI8 x) = VB64 (cast x)
conv TI8 (VI8 x) = VI8 x
conv TI16 (VI8 x) = VI16 (cast x)
conv TI32 (VI8 x) = VI32 (cast x)
conv TI64 (VI8 x) = VI64 (cast x)
conv TI (VI8 x) = VI (cast x)
conv TBI (VI8 x) = VBI (cast x)
conv TB8 (VI16 x) = VB8 (cast x)
conv TB16 (VI16 x) = VB16 (cast x)
conv TB32 (VI16 x) = VB32 (cast x)
conv TB64 (VI16 x) = VB64 (cast x)
conv TI8 (VI16 x) = VI8 (cast x)
conv TI16 (VI16 x) = VI16 x
conv TI32 (VI16 x) = VI32 (cast x)
conv TI64 (VI16 x) = VI64 (cast x)
conv TI (VI16 x) = VI (cast x)
conv TBI (VI16 x) = VBI (cast x)
conv TB8 (VI32 x) = VB8 (cast x)
conv TB16 (VI32 x) = VB16 (cast x)
conv TB32 (VI32 x) = VB32 (cast x)
conv TB64 (VI32 x) = VB64 (cast x)
conv TI8 (VI32 x) = VI8 (cast x)
conv TI16 (VI32 x) = VI16 (cast x)
conv TI32 (VI32 x) = VI32 x
conv TI64 (VI32 x) = VI64 (cast x)
conv TI (VI32 x) = VI (cast x)
conv TBI (VI32 x) = VBI (cast x)
conv TB8 (VI64 x) = VB8 (cast x)
conv TB16 (VI64 x) = VB16 (cast x)
conv TB32 (VI64 x) = VB32 (cast x)
conv TB64 (VI64 x) = VB64 (cast x)
conv TI8 (VI64 x) = VI8 (cast x)
conv TI16 (VI64 x) = VI16 (cast x)
conv TI32 (VI64 x) = VI32 (cast x)
conv TI64 (VI64 x) = VI64 x
conv TI (VI64 x) = VI (cast x)
conv TBI (VI64 x) = VBI (cast x)
conv TB8 (VI x) = VB8 (cast x)
conv TB16 (VI x) = VB16 (cast x)
conv TB32 (VI x) = VB32 (cast x)
conv TB64 (VI x) = VB64 (cast x)
conv TI8 (VI x) = VI8 (cast x)
conv TI16 (VI x) = VI16 (cast x)
conv TI32 (VI x) = VI32 (cast x)
conv TI64 (VI x) = VI64 (cast x)
conv TI (VI x) = VI x
conv TBI (VI x) = VBI (cast x)
conv TB8 (VBI x) = VB8 (cast x)
conv TB16 (VBI x) = VB16 (cast x)
conv TB32 (VBI x) = VB32 (cast x)
conv TB64 (VBI x) = VB64 (cast x)
conv TI8 (VBI x) = VI8 (cast x)
conv TI16 (VBI x) = VI16 (cast x)
conv TI32 (VBI x) = VI32 (cast x)
conv TI64 (VBI x) = VI64 (cast x)
conv TI (VBI x) = VI (cast x)
conv TBI (VBI x) = VBI x

-- The value, and its casts to every type
convs : Val -> String
convs v = showVal v ++ " " ++ joinBy "," (map (\t => showVal (conv t v)) allTys)

-- Casts to every type, then from those to every type
casts2 : Val -> List String
casts2 v = map (\t => "  " ++ convs (conv t v)) allTys

charOf : Val -> String

charOf (VB8 x) = show (ord (the Char (cast x)))
charOf (VB16 x) = show (ord (the Char (cast x)))
charOf (VB32 x) = show (ord (the Char (cast x)))
charOf (VB64 x) = show (ord (the Char (cast x)))
charOf (VI8 x) = show (ord (the Char (cast x)))
charOf (VI16 x) = show (ord (the Char (cast x)))
charOf (VI32 x) = show (ord (the Char (cast x)))
charOf (VI64 x) = show (ord (the Char (cast x)))
charOf (VI x) = show (ord (the Char (cast x)))
charOf (VBI x) = show (ord (the Char (cast x)))

opsB8 : Integer -> List String
opsB8 k =
     [ "B8 " ++ show x ++ " + " ++ show y ++ " = " ++ convs (VB8 (x + y)) | x <- vs, y <- vs ]
  ++ [ "B8 " ++ show x ++ " - " ++ show y ++ " = " ++ convs (VB8 (x - y)) | x <- vs, y <- vs ]
  ++ [ "B8 " ++ show x ++ " * " ++ show y ++ " = " ++ convs (VB8 (x * y)) | x <- vs, y <- vs ]
  ++ [ "B8 negate " ++ show x ++ " = " ++ convs (VB8 (negate x)) | x <- vs ]
  ++ [ "B8 " ++ show x ++ " div,mod,and,or,xor " ++ show y ++ " = " ++ show (map showVal [VB8 (x `div` y), VB8 (x `mod` y), VB8 (prim__and_Bits8 x y), VB8 (prim__or_Bits8 x y), VB8 (prim__xor_Bits8 x y)]) | x <- vs, y <- vs ]
  ++ [ "B8 " ++ show x ++ " <,<=,==,>=,> " ++ show y ++ " = " ++ show [x < y, x <= y, x == y, x >= y, x > y] | x <- vs, y <- vs ]
  where
    vs : List Bits8
    vs = map (\v => fromInteger (v * k)) [1, 200, 255]

shiftsB8 : Integer -> List String
shiftsB8 k =
     [ "B8 " ++ show x ++ " shl " ++ show c ++ " = " ++ convs (VB8 (prim__shl_Bits8 x c)) | x <- vs, c <- cs ]
  ++ [ "B8 " ++ show x ++ " shr " ++ show c ++ " = " ++ convs (VB8 (prim__shr_Bits8 x c)) | x <- vs, c <- cs ]
  where
    vs : List Bits8
    vs = map (\v => fromInteger (v * k)) [1, 255, 131]
    cs : List Bits8
    cs = map (\v => fromInteger (v * k)) [0, 1, 7, 8, 9, 16, 200, 255]

castsB8 : Integer -> List String
castsB8 k = concatMap (\x => ("B8 " ++ show x ++ " char " ++ charOf (VB8 x)) :: casts2 (VB8 x)) vs
  where
    vs : List Bits8
    vs = map (\v => fromInteger (v * k)) [0, 200, 255]

opsB16 : Integer -> List String
opsB16 k =
     [ "B16 " ++ show x ++ " + " ++ show y ++ " = " ++ convs (VB16 (x + y)) | x <- vs, y <- vs ]
  ++ [ "B16 " ++ show x ++ " - " ++ show y ++ " = " ++ convs (VB16 (x - y)) | x <- vs, y <- vs ]
  ++ [ "B16 " ++ show x ++ " * " ++ show y ++ " = " ++ convs (VB16 (x * y)) | x <- vs, y <- vs ]
  ++ [ "B16 negate " ++ show x ++ " = " ++ convs (VB16 (negate x)) | x <- vs ]
  ++ [ "B16 " ++ show x ++ " div,mod,and,or,xor " ++ show y ++ " = " ++ show (map showVal [VB16 (x `div` y), VB16 (x `mod` y), VB16 (prim__and_Bits16 x y), VB16 (prim__or_Bits16 x y), VB16 (prim__xor_Bits16 x y)]) | x <- vs, y <- vs ]
  ++ [ "B16 " ++ show x ++ " <,<=,==,>=,> " ++ show y ++ " = " ++ show [x < y, x <= y, x == y, x >= y, x > y] | x <- vs, y <- vs ]
  where
    vs : List Bits16
    vs = map (\v => fromInteger (v * k)) [1, 32840, 65535]

shiftsB16 : Integer -> List String
shiftsB16 k =
     [ "B16 " ++ show x ++ " shl " ++ show c ++ " = " ++ convs (VB16 (prim__shl_Bits16 x c)) | x <- vs, c <- cs ]
  ++ [ "B16 " ++ show x ++ " shr " ++ show c ++ " = " ++ convs (VB16 (prim__shr_Bits16 x c)) | x <- vs, c <- cs ]
  where
    vs : List Bits16
    vs = map (\v => fromInteger (v * k)) [1, 65535, 32771]
    cs : List Bits16
    cs = map (\v => fromInteger (v * k)) [0, 1, 15, 16, 17, 32, 200, 65535]

castsB16 : Integer -> List String
castsB16 k = concatMap (\x => ("B16 " ++ show x ++ " char " ++ charOf (VB16 x)) :: casts2 (VB16 x)) vs
  where
    vs : List Bits16
    vs = map (\v => fromInteger (v * k)) [0, 200, 255, 32768, 65535]

opsB32 : Integer -> List String
opsB32 k =
     [ "B32 " ++ show x ++ " + " ++ show y ++ " = " ++ convs (VB32 (x + y)) | x <- vs, y <- vs ]
  ++ [ "B32 " ++ show x ++ " - " ++ show y ++ " = " ++ convs (VB32 (x - y)) | x <- vs, y <- vs ]
  ++ [ "B32 " ++ show x ++ " * " ++ show y ++ " = " ++ convs (VB32 (x * y)) | x <- vs, y <- vs ]
  ++ [ "B32 negate " ++ show x ++ " = " ++ convs (VB32 (negate x)) | x <- vs ]
  ++ [ "B32 " ++ show x ++ " div,mod,and,or,xor " ++ show y ++ " = " ++ show (map showVal [VB32 (x `div` y), VB32 (x `mod` y), VB32 (prim__and_Bits32 x y), VB32 (prim__or_Bits32 x y), VB32 (prim__xor_Bits32 x y)]) | x <- vs, y <- vs ]
  ++ [ "B32 " ++ show x ++ " <,<=,==,>=,> " ++ show y ++ " = " ++ show [x < y, x <= y, x == y, x >= y, x > y] | x <- vs, y <- vs ]
  where
    vs : List Bits32
    vs = map (\v => fromInteger (v * k)) [1, 2147483720, 4294967295]

shiftsB32 : Integer -> List String
shiftsB32 k =
     [ "B32 " ++ show x ++ " shl " ++ show c ++ " = " ++ convs (VB32 (prim__shl_Bits32 x c)) | x <- vs, c <- cs ]
  ++ [ "B32 " ++ show x ++ " shr " ++ show c ++ " = " ++ convs (VB32 (prim__shr_Bits32 x c)) | x <- vs, c <- cs ]
  where
    vs : List Bits32
    vs = map (\v => fromInteger (v * k)) [1, 4294967295, 2147483651]
    cs : List Bits32
    cs = map (\v => fromInteger (v * k)) [0, 1, 31, 32, 33, 64, 200]

castsB32 : Integer -> List String
castsB32 k = concatMap (\x => ("B32 " ++ show x ++ " char " ++ charOf (VB32 x)) :: casts2 (VB32 x)) vs
  where
    vs : List Bits32
    vs = map (\v => fromInteger (v * k)) [0, 200, 255, 32768, 65535, 2147483648, 4294967295]

opsB64 : Integer -> List String
opsB64 k =
     [ "B64 " ++ show x ++ " + " ++ show y ++ " = " ++ convs (VB64 (x + y)) | x <- vs, y <- vs ]
  ++ [ "B64 " ++ show x ++ " - " ++ show y ++ " = " ++ convs (VB64 (x - y)) | x <- vs, y <- vs ]
  ++ [ "B64 " ++ show x ++ " * " ++ show y ++ " = " ++ convs (VB64 (x * y)) | x <- vs, y <- vs ]
  ++ [ "B64 negate " ++ show x ++ " = " ++ convs (VB64 (negate x)) | x <- vs ]
  ++ [ "B64 " ++ show x ++ " div,mod,and,or,xor " ++ show y ++ " = " ++ show (map showVal [VB64 (x `div` y), VB64 (x `mod` y), VB64 (prim__and_Bits64 x y), VB64 (prim__or_Bits64 x y), VB64 (prim__xor_Bits64 x y)]) | x <- vs, y <- vs ]
  ++ [ "B64 " ++ show x ++ " <,<=,==,>=,> " ++ show y ++ " = " ++ show [x < y, x <= y, x == y, x >= y, x > y] | x <- vs, y <- vs ]
  where
    vs : List Bits64
    vs = map (\v => fromInteger (v * k)) [1, 9223372036854775880, 18446744073709551615]

shiftsB64 : Integer -> List String
shiftsB64 k =
     [ "B64 " ++ show x ++ " shl " ++ show c ++ " = " ++ convs (VB64 (prim__shl_Bits64 x c)) | x <- vs, c <- cs ]
  ++ [ "B64 " ++ show x ++ " shr " ++ show c ++ " = " ++ convs (VB64 (prim__shr_Bits64 x c)) | x <- vs, c <- cs ]
  where
    vs : List Bits64
    vs = map (\v => fromInteger (v * k)) [1, 18446744073709551615, 9223372036854775811]
    cs : List Bits64
    cs = map (\v => fromInteger (v * k)) [0, 1, 63, 64, 65, 128, 200]

castsB64 : Integer -> List String
castsB64 k = concatMap (\x => ("B64 " ++ show x ++ " char " ++ charOf (VB64 x)) :: casts2 (VB64 x)) vs
  where
    vs : List Bits64
    vs = map (\v => fromInteger (v * k)) [0, 200, 255, 32768, 65535, 2147483648, 4294967295, 9223372036854775808]

opsI8 : Integer -> List String
opsI8 k =
     [ "I8 " ++ show x ++ " + " ++ show y ++ " = " ++ convs (VI8 (x + y)) | x <- vs, y <- vs ]
  ++ [ "I8 " ++ show x ++ " - " ++ show y ++ " = " ++ convs (VI8 (x - y)) | x <- vs, y <- vs ]
  ++ [ "I8 " ++ show x ++ " * " ++ show y ++ " = " ++ convs (VI8 (x * y)) | x <- vs, y <- vs ]
  ++ [ "I8 negate " ++ show x ++ " = " ++ convs (VI8 (negate x)) | x <- vs ]
  ++ [ "I8 " ++ show x ++ " div,mod,and,or,xor " ++ show y ++ " = " ++ show (map showVal [VI8 (x `div` y), VI8 (x `mod` y), VI8 (prim__and_Int8 x y), VI8 (prim__or_Int8 x y), VI8 (prim__xor_Int8 x y)]) | x <- vs, y <- vs ]
  ++ [ "I8 " ++ show x ++ " <,<=,==,>=,> " ++ show y ++ " = " ++ show [x < y, x <= y, x == y, x >= y, x > y] | x <- vs, y <- vs ]
  where
    vs : List Int8
    vs = map (\v => fromInteger (v * k)) [(-1), 127, (-128)]

shiftsI8 : Integer -> List String
shiftsI8 k =
     [ "I8 " ++ show x ++ " shl " ++ show c ++ " = " ++ convs (VI8 (prim__shl_Int8 x c)) | x <- vs, c <- cs ]
  ++ [ "I8 " ++ show x ++ " shr " ++ show c ++ " = " ++ convs (VI8 (prim__shr_Int8 x c)) | x <- vs, c <- cs ]
  ++ [ "I8 " ++ show x ++ " shl " ++ show c ++ " = " ++ convs (VI8 (prim__shl_Int8 x c)) | x <- vs, c <- ns ]
  ++ [ "I8 " ++ show x ++ " shr " ++ show c ++ " = " ++ convs (VI8 (prim__shr_Int8 x c)) | x <- small, c <- smallNs ]
  where
    vs : List Int8
    vs = map (\v => fromInteger (v * k)) [1, (-5), (-128)]
    cs : List Int8
    cs = map (\v => fromInteger (v * k)) [0, 1, 7, 8, 9, 16]
    ns : List Int8
    ns = map (\v => fromInteger (v * k)) [(-128), (-9), (-8), (-7), (-1)]
    small : List Int8
    small = map (\v => fromInteger (v * k)) [1, -3]
    smallNs : List Int8
    smallNs = map (\v => fromInteger (v * k)) [-1, -2]

castsI8 : Integer -> List String
castsI8 k = concatMap (\x => ("I8 " ++ show x ++ " char " ++ charOf (VI8 x)) :: casts2 (VI8 x)) vs
  where
    vs : List Int8
    vs = map (\v => fromInteger (v * k)) [0, (-1), (-56)]

opsI16 : Integer -> List String
opsI16 k =
     [ "I16 " ++ show x ++ " + " ++ show y ++ " = " ++ convs (VI16 (x + y)) | x <- vs, y <- vs ]
  ++ [ "I16 " ++ show x ++ " - " ++ show y ++ " = " ++ convs (VI16 (x - y)) | x <- vs, y <- vs ]
  ++ [ "I16 " ++ show x ++ " * " ++ show y ++ " = " ++ convs (VI16 (x * y)) | x <- vs, y <- vs ]
  ++ [ "I16 negate " ++ show x ++ " = " ++ convs (VI16 (negate x)) | x <- vs ]
  ++ [ "I16 " ++ show x ++ " div,mod,and,or,xor " ++ show y ++ " = " ++ show (map showVal [VI16 (x `div` y), VI16 (x `mod` y), VI16 (prim__and_Int16 x y), VI16 (prim__or_Int16 x y), VI16 (prim__xor_Int16 x y)]) | x <- vs, y <- vs ]
  ++ [ "I16 " ++ show x ++ " <,<=,==,>=,> " ++ show y ++ " = " ++ show [x < y, x <= y, x == y, x >= y, x > y] | x <- vs, y <- vs ]
  where
    vs : List Int16
    vs = map (\v => fromInteger (v * k)) [(-1), 32767, (-32768)]

shiftsI16 : Integer -> List String
shiftsI16 k =
     [ "I16 " ++ show x ++ " shl " ++ show c ++ " = " ++ convs (VI16 (prim__shl_Int16 x c)) | x <- vs, c <- cs ]
  ++ [ "I16 " ++ show x ++ " shr " ++ show c ++ " = " ++ convs (VI16 (prim__shr_Int16 x c)) | x <- vs, c <- cs ]
  ++ [ "I16 " ++ show x ++ " shl " ++ show c ++ " = " ++ convs (VI16 (prim__shl_Int16 x c)) | x <- vs, c <- ns ]
  ++ [ "I16 " ++ show x ++ " shr " ++ show c ++ " = " ++ convs (VI16 (prim__shr_Int16 x c)) | x <- small, c <- smallNs ]
  where
    vs : List Int16
    vs = map (\v => fromInteger (v * k)) [1, (-5), (-32768)]
    cs : List Int16
    cs = map (\v => fromInteger (v * k)) [0, 1, 15, 16, 17, 32, 200]
    ns : List Int16
    ns = map (\v => fromInteger (v * k)) [(-32768), (-17), (-16), (-15), (-1)]
    small : List Int16
    small = map (\v => fromInteger (v * k)) [1, -3]
    smallNs : List Int16
    smallNs = map (\v => fromInteger (v * k)) [-1, -2]

castsI16 : Integer -> List String
castsI16 k = concatMap (\x => ("I16 " ++ show x ++ " char " ++ charOf (VI16 x)) :: casts2 (VI16 x)) vs
  where
    vs : List Int16
    vs = map (\v => fromInteger (v * k)) [0, 200, 255, (-1), (-56), (-129)]

opsI32 : Integer -> List String
opsI32 k =
     [ "I32 " ++ show x ++ " + " ++ show y ++ " = " ++ convs (VI32 (x + y)) | x <- vs, y <- vs ]
  ++ [ "I32 " ++ show x ++ " - " ++ show y ++ " = " ++ convs (VI32 (x - y)) | x <- vs, y <- vs ]
  ++ [ "I32 " ++ show x ++ " * " ++ show y ++ " = " ++ convs (VI32 (x * y)) | x <- vs, y <- vs ]
  ++ [ "I32 negate " ++ show x ++ " = " ++ convs (VI32 (negate x)) | x <- vs ]
  ++ [ "I32 " ++ show x ++ " div,mod,and,or,xor " ++ show y ++ " = " ++ show (map showVal [VI32 (x `div` y), VI32 (x `mod` y), VI32 (prim__and_Int32 x y), VI32 (prim__or_Int32 x y), VI32 (prim__xor_Int32 x y)]) | x <- vs, y <- vs ]
  ++ [ "I32 " ++ show x ++ " <,<=,==,>=,> " ++ show y ++ " = " ++ show [x < y, x <= y, x == y, x >= y, x > y] | x <- vs, y <- vs ]
  where
    vs : List Int32
    vs = map (\v => fromInteger (v * k)) [(-1), 2147483647, (-2147483648)]

shiftsI32 : Integer -> List String
shiftsI32 k =
     [ "I32 " ++ show x ++ " shl " ++ show c ++ " = " ++ convs (VI32 (prim__shl_Int32 x c)) | x <- vs, c <- cs ]
  ++ [ "I32 " ++ show x ++ " shr " ++ show c ++ " = " ++ convs (VI32 (prim__shr_Int32 x c)) | x <- vs, c <- cs ]
  ++ [ "I32 " ++ show x ++ " shl " ++ show c ++ " = " ++ convs (VI32 (prim__shl_Int32 x c)) | x <- vs, c <- ns ]
  ++ [ "I32 " ++ show x ++ " shr " ++ show c ++ " = " ++ convs (VI32 (prim__shr_Int32 x c)) | x <- small, c <- smallNs ]
  where
    vs : List Int32
    vs = map (\v => fromInteger (v * k)) [1, (-5), (-2147483648)]
    cs : List Int32
    cs = map (\v => fromInteger (v * k)) [0, 1, 31, 32, 33, 64, 200]
    ns : List Int32
    ns = map (\v => fromInteger (v * k)) [(-2147483648), (-33), (-32), (-31), (-1)]
    small : List Int32
    small = map (\v => fromInteger (v * k)) [1, -3]
    smallNs : List Int32
    smallNs = map (\v => fromInteger (v * k)) [-1, -2]

castsI32 : Integer -> List String
castsI32 k = concatMap (\x => ("I32 " ++ show x ++ " char " ++ charOf (VI32 x)) :: casts2 (VI32 x)) vs
  where
    vs : List Int32
    vs = map (\v => fromInteger (v * k)) [0, 200, 255, 32768, 65535, (-1), (-56), (-129), (-32769)]

opsI64 : Integer -> List String
opsI64 k =
     [ "I64 " ++ show x ++ " + " ++ show y ++ " = " ++ convs (VI64 (x + y)) | x <- vs, y <- vs ]
  ++ [ "I64 " ++ show x ++ " - " ++ show y ++ " = " ++ convs (VI64 (x - y)) | x <- vs, y <- vs ]
  ++ [ "I64 " ++ show x ++ " * " ++ show y ++ " = " ++ convs (VI64 (x * y)) | x <- vs, y <- vs ]
  ++ [ "I64 negate " ++ show x ++ " = " ++ convs (VI64 (negate x)) | x <- vs ]
  ++ [ "I64 " ++ show x ++ " div,mod,and,or,xor " ++ show y ++ " = " ++ show (map showVal [VI64 (x `div` y), VI64 (x `mod` y), VI64 (prim__and_Int64 x y), VI64 (prim__or_Int64 x y), VI64 (prim__xor_Int64 x y)]) | x <- vs, y <- vs ]
  ++ [ "I64 " ++ show x ++ " <,<=,==,>=,> " ++ show y ++ " = " ++ show [x < y, x <= y, x == y, x >= y, x > y] | x <- vs, y <- vs ]
  where
    vs : List Int64
    vs = map (\v => fromInteger (v * k)) [(-1), 9223372036854775807, (-9223372036854775808)]

shiftsI64 : Integer -> List String
shiftsI64 k =
     [ "I64 " ++ show x ++ " shl " ++ show c ++ " = " ++ convs (VI64 (prim__shl_Int64 x c)) | x <- vs, c <- cs ]
  ++ [ "I64 " ++ show x ++ " shr " ++ show c ++ " = " ++ convs (VI64 (prim__shr_Int64 x c)) | x <- vs, c <- cs ]
  ++ [ "I64 " ++ show x ++ " shl " ++ show c ++ " = " ++ convs (VI64 (prim__shl_Int64 x c)) | x <- vs, c <- ns ]
  ++ [ "I64 " ++ show x ++ " shr " ++ show c ++ " = " ++ convs (VI64 (prim__shr_Int64 x c)) | x <- small, c <- smallNs ]
  where
    vs : List Int64
    vs = map (\v => fromInteger (v * k)) [1, (-5), (-9223372036854775808)]
    cs : List Int64
    cs = map (\v => fromInteger (v * k)) [0, 1, 63, 64, 65, 128, 200]
    ns : List Int64
    ns = map (\v => fromInteger (v * k)) [(-9223372036854775808), (-65), (-64), (-63), (-1)]
    small : List Int64
    small = map (\v => fromInteger (v * k)) [1, -3]
    smallNs : List Int64
    smallNs = map (\v => fromInteger (v * k)) [-1, -2]

castsI64 : Integer -> List String
castsI64 k = concatMap (\x => ("I64 " ++ show x ++ " char " ++ charOf (VI64 x)) :: casts2 (VI64 x)) vs
  where
    vs : List Int64
    vs = map (\v => fromInteger (v * k)) [0, 200, 255, 32768, 65535, 2147483648, 4294967295, (-1), (-56), (-129), (-32769), (-2147483649)]

opsI : Integer -> List String
opsI k =
     [ "I " ++ show x ++ " + " ++ show y ++ " = " ++ convs (VI (x + y)) | x <- vs, y <- vs ]
  ++ [ "I " ++ show x ++ " - " ++ show y ++ " = " ++ convs (VI (x - y)) | x <- vs, y <- vs ]
  ++ [ "I " ++ show x ++ " * " ++ show y ++ " = " ++ convs (VI (x * y)) | x <- vs, y <- vs ]
  ++ [ "I negate " ++ show x ++ " = " ++ convs (VI (negate x)) | x <- vs ]
  ++ [ "I " ++ show x ++ " div,mod,and,or,xor " ++ show y ++ " = " ++ show (map showVal [VI (x `div` y), VI (x `mod` y), VI (prim__and_Int x y), VI (prim__or_Int x y), VI (prim__xor_Int x y)]) | x <- vs, y <- vs ]
  ++ [ "I " ++ show x ++ " <,<=,==,>=,> " ++ show y ++ " = " ++ show [x < y, x <= y, x == y, x >= y, x > y] | x <- vs, y <- vs ]
  where
    vs : List Int
    vs = map (\v => fromInteger (v * k)) [(-1), 9223372036854775807, (-9223372036854775808)]

shiftsI : Integer -> List String
shiftsI k =
     [ "I " ++ show x ++ " shl " ++ show c ++ " = " ++ convs (VI (prim__shl_Int x c)) | x <- vs, c <- cs ]
  ++ [ "I " ++ show x ++ " shr " ++ show c ++ " = " ++ convs (VI (prim__shr_Int x c)) | x <- vs, c <- cs ]
  ++ [ "I " ++ show x ++ " shl " ++ show c ++ " = " ++ convs (VI (prim__shl_Int x c)) | x <- vs, c <- ns ]
  ++ [ "I " ++ show x ++ " shr " ++ show c ++ " = " ++ convs (VI (prim__shr_Int x c)) | x <- small, c <- smallNs ]
  where
    vs : List Int
    vs = map (\v => fromInteger (v * k)) [1, (-5), (-9223372036854775808)]
    cs : List Int
    cs = map (\v => fromInteger (v * k)) [0, 1, 63, 64, 65, 128, 200]
    ns : List Int
    ns = map (\v => fromInteger (v * k)) [(-9223372036854775808), (-65), (-64), (-63), (-1)]
    small : List Int
    small = map (\v => fromInteger (v * k)) [1, -3]
    smallNs : List Int
    smallNs = map (\v => fromInteger (v * k)) [-1, -2]

castsI : Integer -> List String
castsI k = concatMap (\x => ("I " ++ show x ++ " char " ++ charOf (VI x)) :: casts2 (VI x)) vs
  where
    vs : List Int
    vs = map (\v => fromInteger (v * k)) [0, 200, 255, 32768, 65535, 2147483648, 4294967295, (-1), (-56), (-129), (-32769), (-2147483649)]

opsBI : Integer -> List String
opsBI k =
     [ "BI " ++ show x ++ " + " ++ show y ++ " = " ++ convs (VBI (x + y)) | x <- vs, y <- vs ]
  ++ [ "BI " ++ show x ++ " - " ++ show y ++ " = " ++ convs (VBI (x - y)) | x <- vs, y <- vs ]
  ++ [ "BI " ++ show x ++ " * " ++ show y ++ " = " ++ convs (VBI (x * y)) | x <- vs, y <- vs ]
  ++ [ "BI negate " ++ show x ++ " = " ++ convs (VBI (negate x)) | x <- vs ]
  ++ [ "BI " ++ show x ++ " div,mod,and,or,xor " ++ show y ++ " = " ++ show (map showVal [VBI (x `div` y), VBI (x `mod` y), VBI (prim__and_Integer x y), VBI (prim__or_Integer x y), VBI (prim__xor_Integer x y)]) | x <- vs, y <- vs ]
  ++ [ "BI " ++ show x ++ " <,<=,==,>=,> " ++ show y ++ " = " ++ show [x < y, x <= y, x == y, x >= y, x > y] | x <- vs, y <- vs ]
  where
    vs : List Integer
    vs = map (\v => fromInteger (v * k)) [(-3), 1099511627776, (-1180591620717411303424)]

shiftsBI : Integer -> List String
shiftsBI k =
     [ "BI " ++ show x ++ " shl " ++ show c ++ " = " ++ convs (VBI (prim__shl_Integer x c)) | x <- vs, c <- cs ]
  ++ [ "BI " ++ show x ++ " shr " ++ show c ++ " = " ++ convs (VBI (prim__shr_Integer x c)) | x <- vs, c <- cs ]
  ++ [ "BI " ++ show x ++ " shl " ++ show c ++ " = " ++ convs (VBI (prim__shl_Integer x c)) | x <- vs, c <- ns ]
  ++ [ "BI " ++ show x ++ " shr " ++ show c ++ " = " ++ convs (VBI (prim__shr_Integer x c)) | x <- small, c <- smallNs ]
  where
    vs : List Integer
    vs = map (\v => fromInteger (v * k)) [(-5), 1099511627779, (-1180591620717411303425)]
    cs : List Integer
    cs = map (\v => fromInteger (v * k)) [0, 3, 32, 64, 100]
    ns : List Integer
    ns = map (\v => fromInteger (v * k)) [(-3), (-100)]
    small : List Integer
    small = map (\v => fromInteger (v * k)) [1, -3]
    smallNs : List Integer
    smallNs = map (\v => fromInteger (v * k)) [-1, -2]

castsBI : Integer -> List String
castsBI k = concatMap (\x => ("BI " ++ show x ++ " char " ++ charOf (VBI x)) :: casts2 (VBI x)) vs
  where
    vs : List Integer
    vs = map (\v => fromInteger (v * k)) [0, 200, 255, 32768, 65535, 2147483648, 4294967295, 9223372036854775808, 18446744073709551621, (-1), (-56), (-129), (-32769), (-2147483649), (-9223372036854775809)]

-- Double to the integer types: truncated, then wrapped around
doubles : Integer -> List String
doubles k = map (\d => "Double " ++ show (cast {to = Integer} d) ++ " " ++ dblCasts d) ds
  where
    ds : List Double
    ds = map (\d => d * cast k) [0.0, 1.9, -1.9, 255.5, 256.7, -128.5, -129.5, 65535.9, 2147483648.5, -2147483649.5, 4294967296.0, 9200000000000000000.0, 9300000000000000000.0, -9300000000000000000.0, 18446744073709551616.0] ++ [1000000000000000.0 * 1000000000000000.0, -1000000000000000.0 * 1000000000000000.0]
    dblCasts : Double -> String
    dblCasts d = show (map showVal [VB8 (cast d), VB16 (cast d), VB32 (cast d), VB64 (cast d), VI8 (cast d), VI16 (cast d), VI32 (cast d), VI64 (cast d), VI (cast d), VBI (cast d)])

-- Char to the integer types, and back
chars : Integer -> List String
chars k = map (\c => "Char " ++ show (ord c) ++ " " ++ charCasts c) cs
  where
    cs : List Char
    cs = map (\n => cast (n * cast k)) [0, 65, 127, 128, 200, 255, 256, 0xE9, 0x3B1, 0xFFFF, 0x10000, 0x10FFFF]
    charCasts : Char -> String
    charCasts c = show (map showVal [VB8 (cast c), VB16 (cast c), VB32 (cast c), VB64 (cast c), VI8 (cast c), VI16 (cast c), VI32 (cast c), VI64 (cast c), VI (cast c)])

-- The shifts of Ints in a loop, on C integers (see Compiler.RefC.Unbox)
shlLoop : Int -> Int -> List Int -> List Int
shlLoop x c acc = if c > 70 then acc else shlLoop x (c + 1) (prim__shl_Int x c :: acc)

shrLoop : Int -> Int -> List Int -> List Int
shrLoop x c acc = if c > 70 then acc else shrLoop x (c + 1) (prim__shr_Int x c :: acc)

-- (shl by a negative count shifts right)
shlNegLoop : Int -> Int -> List Int -> List Int
shlNegLoop x c acc = if c < -70 then acc else shlNegLoop x (c - 1) (prim__shl_Int x c :: acc)

arithLoop : Int -> Int -> Int -> List Int -> List Int
arithLoop x y n acc
    = if n == 0 then acc
         else arithLoop (x * 3 + y) (y - x * 5) (n - 1) (x :: y :: acc)

intLoops : Int -> List String
intLoops k =
  [ "Int loop shl 1: " ++ show (reverse (shlLoop k 0 []))
  , "Int loop shl -3: " ++ show (reverse (shlLoop (-3 * k) 0 []))
  , "Int loop shr max: " ++ show (reverse (shrLoop (9223372036854775807 * k) 0 []))
  , "Int loop shr min: " ++ show (reverse (shrLoop (-9223372036854775807 * k - 1) 0 []))
  , "Int loop shl neg: " ++ show (reverse (shlNegLoop (-9223372036854775807 * k - 1) (-1) []))
  , "Int loop arith: " ++ show (reverse (arithLoop (k * 123456789) (k * 987654321) 40 []))
  ]

-- Constant expressions, which the compiler folds
folded : List String
folded =
  [ show (cast {to = Bits16} (the Bits8 200 + 200))
  , show (cast {to = Int32} (the Bits8 200 - 201))
  , show (cast {to = Int16} (the Int8 127 + 1))
  , show (prim__shl_Bits32 1 32, prim__shl_Bits8 1 8, prim__shl_Int 1 64, prim__shr_Int (-8) 64)
  , show (prim__shl_Int8 1 (-1), prim__shl_Int (-8) (-2), prim__shr_Int8 3 (-2))
  , show (prim__shl_Integer 1024 (-3), prim__shr_Integer 1024 (-3))
  , show (cast {to = Int8} (the Bits8 200), cast {to = Bits8} (the Int8 (-1)))
  ]

-- Shifts of Integers by negative counts go the other way
integerShifts : Integer -> List String
integerShifts k =
  [ show [prim__shl_Integer x c | x <- xs, c <- cs]
  , show [prim__shr_Integer x c | x <- xs, c <- cs]
  ]
  where
    xs : List Integer
    xs = map (* k) [1024, -1024, 3, -3, 1208925819614629174706183, -1208925819614629174706183]
    cs : List Integer
    cs = map (* k) [0, 3, -3, 70, -70, 100, -100]

-- The examples of the bug report
examples : Integer -> List String
examples k =
  let x : Bits8 = fromInteger (200 * k) in
  [ show (cast {to = Bits16} (x + 200))
  , show (cast {to = Int32} (x - 201))
  , case x + 200 of { 144 => "ok"; _ => "wrong" }
  , case the Bits8 (cast (the Int8 (fromInteger (-k)))) of { 255 => "ok"; _ => "wrong" }
  , case the Int8 (cast x) of { -56 => "ok"; _ => "wrong" }
  , show (prim__shl_Bits32 (fromInteger k) 32)
  ]

-- To compare with the Chez backend (whose results are the specification):
--   idris2 --cg chez -o fw FixedWidth.idr && ./build/exec/fw
main : IO ()
main = do
  k <- cast . length <$> getArgs
  traverse_ putStrLn (examples k)
  traverse_ putStrLn folded
  traverse_ putStrLn (intLoops (cast k))
  traverse_ putStrLn (integerShifts k)
  traverse_ putStrLn (doubles k)
  traverse_ putStrLn (chars k)

  traverse_ putStrLn (opsB8 k)
  traverse_ putStrLn (shiftsB8 k)
  traverse_ putStrLn (castsB8 k)
  traverse_ putStrLn (opsB16 k)
  traverse_ putStrLn (shiftsB16 k)
  traverse_ putStrLn (castsB16 k)
  traverse_ putStrLn (opsB32 k)
  traverse_ putStrLn (shiftsB32 k)
  traverse_ putStrLn (castsB32 k)
  traverse_ putStrLn (opsB64 k)
  traverse_ putStrLn (shiftsB64 k)
  traverse_ putStrLn (castsB64 k)
  traverse_ putStrLn (opsI8 k)
  traverse_ putStrLn (shiftsI8 k)
  traverse_ putStrLn (castsI8 k)
  traverse_ putStrLn (opsI16 k)
  traverse_ putStrLn (shiftsI16 k)
  traverse_ putStrLn (castsI16 k)
  traverse_ putStrLn (opsI32 k)
  traverse_ putStrLn (shiftsI32 k)
  traverse_ putStrLn (castsI32 k)
  traverse_ putStrLn (opsI64 k)
  traverse_ putStrLn (shiftsI64 k)
  traverse_ putStrLn (castsI64 k)
  traverse_ putStrLn (opsI k)
  traverse_ putStrLn (shiftsI k)
  traverse_ putStrLn (castsI k)
  traverse_ putStrLn (opsBI k)
  traverse_ putStrLn (shiftsBI k)
  traverse_ putStrLn (castsBI k)
