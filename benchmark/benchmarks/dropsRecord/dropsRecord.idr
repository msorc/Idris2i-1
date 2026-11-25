||| Taking apart a value of K fields as the hot path.  In the cases
||| `uK_N` the value is made at every step (it is unique: its unused fields
||| are released and its cell freed), in the cases `sK_N` the loop keeps it
||| (it is shared: the fields that are used get references, and the value
||| loses one).  N is the number of fields used: `pK_1` and `pK_2` take
||| apart a record and use one or two of its fields; for N = 0 the loop
||| matches a constructor of a type with two (made by `mkK`, or given back
||| by `idK`) and uses none of them.  The fields are strings that the loop
||| keeps.
|||
||| Every line of the input is `CASE STEPS`, e.g. `u8_1 1000000`.
module Main

import Data.String

%default partial

record R4 where
  constructor MkR4
  f1, f2, f3, f4 : String

data S4 = A4 String String String String | B4

record R8 where
  constructor MkR8
  f1, f2, f3, f4, f5, f6, f7, f8 : String

data S8 = A8 String String String String String String String String | B8

record R16 where
  constructor MkR16
  f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14, f15, f16 : String

data S16 = A16 String String String String String String String String String String String String String String String String | B16

%noinline
p4_1 : R4 -> String
p4_1 (MkR4 a b _ _) = a

%noinline
p4_2 : R4 -> (String, String)
p4_2 (MkR4 a b _ _) = (b, a)

%noinline
mk4 : String -> String -> String -> String -> S4
mk4 s1 s2 s3 s4 = A4 s1 s2 s3 s4

%noinline
id4 : S4 -> S4
id4 x = x

%noinline
p8_1 : R8 -> String
p8_1 (MkR8 a b _ _ _ _ _ _) = a

%noinline
p8_2 : R8 -> (String, String)
p8_2 (MkR8 a b _ _ _ _ _ _) = (b, a)

%noinline
mk8 : String -> String -> String -> String -> S8
mk8 s1 s2 s3 s4 = A8 s1 s2 s3 s4 s1 s2 s3 s4

%noinline
id8 : S8 -> S8
id8 x = x

%noinline
p16_1 : R16 -> String
p16_1 (MkR16 a b _ _ _ _ _ _ _ _ _ _ _ _ _ _) = a

%noinline
p16_2 : R16 -> (String, String)
p16_2 (MkR16 a b _ _ _ _ _ _ _ _ _ _ _ _ _ _) = (b, a)

%noinline
mk16 : String -> String -> String -> String -> S16
mk16 s1 s2 s3 s4 = A16 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4

%noinline
id16 : S16 -> S16
id16 x = x

u4_0 : String -> String -> String -> String -> Int -> Int -> Int
u4_0 s1 s2 s3 s4 0 acc = acc
u4_0 s1 s2 s3 s4 n acc =
  u4_0 s1 s2 s3 s4 (n - 1) (acc + (case mk4 s1 s2 s3 s4 of { A4 _ _ _ _ => 1; B4 => 2 }))

s4_0 : S4 -> Int -> Int -> Int
s4_0 r 0 acc = acc
s4_0 r n acc = s4_0 r (n - 1) (acc + (case id4 r of { A4 _ _ _ _ => 1; B4 => 2 }))

u4_1 : String -> String -> String -> String -> Int -> Int -> Int
u4_1 s1 s2 s3 s4 0 acc = acc
u4_1 s1 s2 s3 s4 n acc =
  let r = MkR4 s1 s2 s3 s4 in
  u4_1 s1 s2 s3 s4 (n - 1) (acc + strLength (p4_1 r))

s4_1 : R4 -> Int -> Int -> Int
s4_1 r 0 acc = acc
s4_1 r n acc = s4_1 r (n - 1) (acc + strLength (p4_1 r))

u4_2 : String -> String -> String -> String -> Int -> Int -> Int
u4_2 s1 s2 s3 s4 0 acc = acc
u4_2 s1 s2 s3 s4 n acc =
  let r = MkR4 s1 s2 s3 s4 in
  u4_2 s1 s2 s3 s4 (n - 1) (acc + (let (x, y) = p4_2 r in strLength x + strLength y))

s4_2 : R4 -> Int -> Int -> Int
s4_2 r 0 acc = acc
s4_2 r n acc = s4_2 r (n - 1) (acc + (let (x, y) = p4_2 r in strLength x + strLength y))

u8_0 : String -> String -> String -> String -> Int -> Int -> Int
u8_0 s1 s2 s3 s4 0 acc = acc
u8_0 s1 s2 s3 s4 n acc =
  u8_0 s1 s2 s3 s4 (n - 1) (acc + (case mk8 s1 s2 s3 s4 of { A8 _ _ _ _ _ _ _ _ => 1; B8 => 2 }))

s8_0 : S8 -> Int -> Int -> Int
s8_0 r 0 acc = acc
s8_0 r n acc = s8_0 r (n - 1) (acc + (case id8 r of { A8 _ _ _ _ _ _ _ _ => 1; B8 => 2 }))

u8_1 : String -> String -> String -> String -> Int -> Int -> Int
u8_1 s1 s2 s3 s4 0 acc = acc
u8_1 s1 s2 s3 s4 n acc =
  let r = MkR8 s1 s2 s3 s4 s1 s2 s3 s4 in
  u8_1 s1 s2 s3 s4 (n - 1) (acc + strLength (p8_1 r))

s8_1 : R8 -> Int -> Int -> Int
s8_1 r 0 acc = acc
s8_1 r n acc = s8_1 r (n - 1) (acc + strLength (p8_1 r))

u8_2 : String -> String -> String -> String -> Int -> Int -> Int
u8_2 s1 s2 s3 s4 0 acc = acc
u8_2 s1 s2 s3 s4 n acc =
  let r = MkR8 s1 s2 s3 s4 s1 s2 s3 s4 in
  u8_2 s1 s2 s3 s4 (n - 1) (acc + (let (x, y) = p8_2 r in strLength x + strLength y))

s8_2 : R8 -> Int -> Int -> Int
s8_2 r 0 acc = acc
s8_2 r n acc = s8_2 r (n - 1) (acc + (let (x, y) = p8_2 r in strLength x + strLength y))

u16_0 : String -> String -> String -> String -> Int -> Int -> Int
u16_0 s1 s2 s3 s4 0 acc = acc
u16_0 s1 s2 s3 s4 n acc =
  u16_0 s1 s2 s3 s4 (n - 1) (acc + (case mk16 s1 s2 s3 s4 of { A16 _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ => 1; B16 => 2 }))

s16_0 : S16 -> Int -> Int -> Int
s16_0 r 0 acc = acc
s16_0 r n acc = s16_0 r (n - 1) (acc + (case id16 r of { A16 _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ => 1; B16 => 2 }))

u16_1 : String -> String -> String -> String -> Int -> Int -> Int
u16_1 s1 s2 s3 s4 0 acc = acc
u16_1 s1 s2 s3 s4 n acc =
  let r = MkR16 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4 in
  u16_1 s1 s2 s3 s4 (n - 1) (acc + strLength (p16_1 r))

s16_1 : R16 -> Int -> Int -> Int
s16_1 r 0 acc = acc
s16_1 r n acc = s16_1 r (n - 1) (acc + strLength (p16_1 r))

u16_2 : String -> String -> String -> String -> Int -> Int -> Int
u16_2 s1 s2 s3 s4 0 acc = acc
u16_2 s1 s2 s3 s4 n acc =
  let r = MkR16 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4 in
  u16_2 s1 s2 s3 s4 (n - 1) (acc + (let (x, y) = p16_2 r in strLength x + strLength y))

s16_2 : R16 -> Int -> Int -> Int
s16_2 r 0 acc = acc
s16_2 r n acc = s16_2 r (n - 1) (acc + (let (x, y) = p16_2 r in strLength x + strLength y))

runCase : String -> Int -> Maybe Int
runCase c n =
  let s1 = pack ['a', 'b']
      s2 = pack ['c', 'd']
      s3 = pack ['e', 'f']
      s4 = pack ['g', 'h'] in
  case c of
    "u4_0" => Just (u4_0 s1 s2 s3 s4 n 0)
    "s4_0" => Just (s4_0 (A4 s1 s2 s3 s4) n 0)
    "u4_1" => Just (u4_1 s1 s2 s3 s4 n 0)
    "s4_1" => Just (s4_1 (MkR4 s1 s2 s3 s4) n 0)
    "u4_2" => Just (u4_2 s1 s2 s3 s4 n 0)
    "s4_2" => Just (s4_2 (MkR4 s1 s2 s3 s4) n 0)
    "u8_0" => Just (u8_0 s1 s2 s3 s4 n 0)
    "s8_0" => Just (s8_0 (A8 s1 s2 s3 s4 s1 s2 s3 s4) n 0)
    "u8_1" => Just (u8_1 s1 s2 s3 s4 n 0)
    "s8_1" => Just (s8_1 (MkR8 s1 s2 s3 s4 s1 s2 s3 s4) n 0)
    "u8_2" => Just (u8_2 s1 s2 s3 s4 n 0)
    "s8_2" => Just (s8_2 (MkR8 s1 s2 s3 s4 s1 s2 s3 s4) n 0)
    "u16_0" => Just (u16_0 s1 s2 s3 s4 n 0)
    "s16_0" => Just (s16_0 (A16 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4) n 0)
    "u16_1" => Just (u16_1 s1 s2 s3 s4 n 0)
    "s16_1" => Just (s16_1 (MkR16 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4) n 0)
    "u16_2" => Just (u16_2 s1 s2 s3 s4 n 0)
    "s16_2" => Just (s16_2 (MkR16 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4) n 0)
    _ => Nothing

runLine : String -> IO ()
runLine l =
  case words l of
    [c, n] => case runCase c (cast n) of
                   Just r => putStrLn "\{c} \{show r}"
                   Nothing => putStrLn "unknown case \{c}"
    _ => pure ()

main : IO ()
main = loop
  where
    loop : IO ()
    loop = do l <- getLine
              if l == ""
                 then pure ()
                 else do runLine l; loop
