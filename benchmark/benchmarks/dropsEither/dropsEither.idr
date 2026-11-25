||| The error arm of an inlined bind of `Either` as the hot path.
|||
||| `check` fails at every call, so every step of the loops below runs the
||| `Left` arm of the bind in `eK`/`nK`: the values that the continuation
||| captured (K of them) are released and the `Left` is returned.  `eK`
||| has the bind in tail position, `nK` gives its result to another
||| function.  The case `e<t|n><b|u|m>K` runs `eK` (t) or `nK` (n) with
||| values that are, by the letter: `b` strings that the loop keeps (only
||| their counts go down), `u` characters (unboxed values), `m` a mix of
||| kept strings, characters, string literals (immortal) and lists made
||| at every step (released at every step).
|||
||| Every line of the input is `CASE STEPS`, e.g. `etb8 1000000`; the
||| program prints a checksum for each.
module Main

import Data.String

%default partial

-- Fails at every call: the counters are never negative.
%noinline
check : Int -> Either Int Int
check i = if i >= 0 then Left i else Right (i + 1)

%inline
bind : Either e a -> (a -> Either e b) -> Either e b
bind (Left e) _ = Left e
bind (Right x) k = k x

%noinline
finish : Either Int b -> Either Int b
finish r = r

data T2 a1 a2 = MkT2 a1 a2

data T4 a1 a2 a3 a4 = MkT4 a1 a2 a3 a4

data T8 a1 a2 a3 a4 a5 a6 a7 a8 = MkT8 a1 a2 a3 a4 a5 a6 a7 a8

data T16 a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16 = MkT16 a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16

%noinline
e2 : Int -> a1 -> a2 -> Either Int (T2 a1 a2)
e2 i v1 v2 = check i `bind` \x => Right (MkT2 v1 v2)

%noinline
n2 : Int -> a1 -> a2 -> Either Int (T2 a1 a2)
n2 i v1 v2 = finish (check i `bind` \x => Right (MkT2 v1 v2))

%noinline
e4 : Int -> a1 -> a2 -> a3 -> a4 -> Either Int (T4 a1 a2 a3 a4)
e4 i v1 v2 v3 v4 = check i `bind` \x => Right (MkT4 v1 v2 v3 v4)

%noinline
n4 : Int -> a1 -> a2 -> a3 -> a4 -> Either Int (T4 a1 a2 a3 a4)
n4 i v1 v2 v3 v4 = finish (check i `bind` \x => Right (MkT4 v1 v2 v3 v4))

%noinline
e8 : Int -> a1 -> a2 -> a3 -> a4 -> a5 -> a6 -> a7 -> a8 -> Either Int (T8 a1 a2 a3 a4 a5 a6 a7 a8)
e8 i v1 v2 v3 v4 v5 v6 v7 v8 = check i `bind` \x => Right (MkT8 v1 v2 v3 v4 v5 v6 v7 v8)

%noinline
n8 : Int -> a1 -> a2 -> a3 -> a4 -> a5 -> a6 -> a7 -> a8 -> Either Int (T8 a1 a2 a3 a4 a5 a6 a7 a8)
n8 i v1 v2 v3 v4 v5 v6 v7 v8 = finish (check i `bind` \x => Right (MkT8 v1 v2 v3 v4 v5 v6 v7 v8))

%noinline
e16 : Int -> a1 -> a2 -> a3 -> a4 -> a5 -> a6 -> a7 -> a8 -> a9 -> a10 -> a11 -> a12 -> a13 -> a14 -> a15 -> a16 -> Either Int (T16 a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16)
e16 i v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 v16 = check i `bind` \x => Right (MkT16 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 v16)

%noinline
n16 : Int -> a1 -> a2 -> a3 -> a4 -> a5 -> a6 -> a7 -> a8 -> a9 -> a10 -> a11 -> a12 -> a13 -> a14 -> a15 -> a16 -> Either Int (T16 a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16)
n16 i v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 v16 = finish (check i `bind` \x => Right (MkT16 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 v16))

etb2 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
etb2 s1 s2 s3 s4 c1 c2 0 acc = acc
etb2 s1 s2 s3 s4 c1 c2 n acc = case e2 n s1 s2 of
  Left e => etb2 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

etb4 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
etb4 s1 s2 s3 s4 c1 c2 0 acc = acc
etb4 s1 s2 s3 s4 c1 c2 n acc = case e4 n s1 s2 s3 s4 of
  Left e => etb4 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

etb8 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
etb8 s1 s2 s3 s4 c1 c2 0 acc = acc
etb8 s1 s2 s3 s4 c1 c2 n acc = case e8 n s1 s2 s3 s4 s1 s2 s3 s4 of
  Left e => etb8 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

etb16 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
etb16 s1 s2 s3 s4 c1 c2 0 acc = acc
etb16 s1 s2 s3 s4 c1 c2 n acc = case e16 n s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4 of
  Left e => etb16 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

etu2 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
etu2 s1 s2 s3 s4 c1 c2 0 acc = acc
etu2 s1 s2 s3 s4 c1 c2 n acc = case e2 n c1 c2 of
  Left e => etu2 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

etu4 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
etu4 s1 s2 s3 s4 c1 c2 0 acc = acc
etu4 s1 s2 s3 s4 c1 c2 n acc = case e4 n c1 c2 c1 c2 of
  Left e => etu4 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

etu8 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
etu8 s1 s2 s3 s4 c1 c2 0 acc = acc
etu8 s1 s2 s3 s4 c1 c2 n acc = case e8 n c1 c2 c1 c2 c1 c2 c1 c2 of
  Left e => etu8 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

etu16 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
etu16 s1 s2 s3 s4 c1 c2 0 acc = acc
etu16 s1 s2 s3 s4 c1 c2 n acc = case e16 n c1 c2 c1 c2 c1 c2 c1 c2 c1 c2 c1 c2 c1 c2 c1 c2 of
  Left e => etu16 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

etm2 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
etm2 s1 s2 s3 s4 c1 c2 0 acc = acc
etm2 s1 s2 s3 s4 c1 c2 n acc = case e2 n s1 c1 of
  Left e => etm2 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

etm4 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
etm4 s1 s2 s3 s4 c1 c2 0 acc = acc
etm4 s1 s2 s3 s4 c1 c2 n acc = case e4 n s1 c1 "lit" [n] of
  Left e => etm4 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

etm8 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
etm8 s1 s2 s3 s4 c1 c2 0 acc = acc
etm8 s1 s2 s3 s4 c1 c2 n acc = case e8 n s1 c1 "lit" [n] s2 c1 "lit" [n] of
  Left e => etm8 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

etm16 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
etm16 s1 s2 s3 s4 c1 c2 0 acc = acc
etm16 s1 s2 s3 s4 c1 c2 n acc = case e16 n s1 c1 "lit" [n] s2 c1 "lit" [n] s3 c1 "lit" [n] s4 c1 "lit" [n] of
  Left e => etm16 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

enb2 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
enb2 s1 s2 s3 s4 c1 c2 0 acc = acc
enb2 s1 s2 s3 s4 c1 c2 n acc = case n2 n s1 s2 of
  Left e => enb2 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

enb4 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
enb4 s1 s2 s3 s4 c1 c2 0 acc = acc
enb4 s1 s2 s3 s4 c1 c2 n acc = case n4 n s1 s2 s3 s4 of
  Left e => enb4 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

enb8 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
enb8 s1 s2 s3 s4 c1 c2 0 acc = acc
enb8 s1 s2 s3 s4 c1 c2 n acc = case n8 n s1 s2 s3 s4 s1 s2 s3 s4 of
  Left e => enb8 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

enb16 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
enb16 s1 s2 s3 s4 c1 c2 0 acc = acc
enb16 s1 s2 s3 s4 c1 c2 n acc = case n16 n s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4 of
  Left e => enb16 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

enu2 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
enu2 s1 s2 s3 s4 c1 c2 0 acc = acc
enu2 s1 s2 s3 s4 c1 c2 n acc = case n2 n c1 c2 of
  Left e => enu2 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

enu4 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
enu4 s1 s2 s3 s4 c1 c2 0 acc = acc
enu4 s1 s2 s3 s4 c1 c2 n acc = case n4 n c1 c2 c1 c2 of
  Left e => enu4 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

enu8 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
enu8 s1 s2 s3 s4 c1 c2 0 acc = acc
enu8 s1 s2 s3 s4 c1 c2 n acc = case n8 n c1 c2 c1 c2 c1 c2 c1 c2 of
  Left e => enu8 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

enu16 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
enu16 s1 s2 s3 s4 c1 c2 0 acc = acc
enu16 s1 s2 s3 s4 c1 c2 n acc = case n16 n c1 c2 c1 c2 c1 c2 c1 c2 c1 c2 c1 c2 c1 c2 c1 c2 of
  Left e => enu16 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

enm2 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
enm2 s1 s2 s3 s4 c1 c2 0 acc = acc
enm2 s1 s2 s3 s4 c1 c2 n acc = case n2 n s1 c1 of
  Left e => enm2 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

enm4 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
enm4 s1 s2 s3 s4 c1 c2 0 acc = acc
enm4 s1 s2 s3 s4 c1 c2 n acc = case n4 n s1 c1 "lit" [n] of
  Left e => enm4 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

enm8 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
enm8 s1 s2 s3 s4 c1 c2 0 acc = acc
enm8 s1 s2 s3 s4 c1 c2 n acc = case n8 n s1 c1 "lit" [n] s2 c1 "lit" [n] of
  Left e => enm8 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

enm16 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
enm16 s1 s2 s3 s4 c1 c2 0 acc = acc
enm16 s1 s2 s3 s4 c1 c2 n acc = case n16 n s1 c1 "lit" [n] s2 c1 "lit" [n] s3 c1 "lit" [n] s4 c1 "lit" [n] of
  Left e => enm16 s1 s2 s3 s4 c1 c2 (n - 1) (acc + e)
  Right _ => acc

-- The strings that the loops keep are made at run time (not literals).
runCase : String -> Int -> Maybe Int
runCase c n =
  let s1 = pack ['a', 'b']
      s2 = pack ['c', 'd']
      s3 = pack ['e', 'f']
      s4 = pack ['g', 'h']
      c1 = 'x'
      c2 = 'y' in
  case c of
    "etb2" => Just (etb2 s1 s2 s3 s4 c1 c2 n 0)
    "etb4" => Just (etb4 s1 s2 s3 s4 c1 c2 n 0)
    "etb8" => Just (etb8 s1 s2 s3 s4 c1 c2 n 0)
    "etb16" => Just (etb16 s1 s2 s3 s4 c1 c2 n 0)
    "etu2" => Just (etu2 s1 s2 s3 s4 c1 c2 n 0)
    "etu4" => Just (etu4 s1 s2 s3 s4 c1 c2 n 0)
    "etu8" => Just (etu8 s1 s2 s3 s4 c1 c2 n 0)
    "etu16" => Just (etu16 s1 s2 s3 s4 c1 c2 n 0)
    "etm2" => Just (etm2 s1 s2 s3 s4 c1 c2 n 0)
    "etm4" => Just (etm4 s1 s2 s3 s4 c1 c2 n 0)
    "etm8" => Just (etm8 s1 s2 s3 s4 c1 c2 n 0)
    "etm16" => Just (etm16 s1 s2 s3 s4 c1 c2 n 0)
    "enb2" => Just (enb2 s1 s2 s3 s4 c1 c2 n 0)
    "enb4" => Just (enb4 s1 s2 s3 s4 c1 c2 n 0)
    "enb8" => Just (enb8 s1 s2 s3 s4 c1 c2 n 0)
    "enb16" => Just (enb16 s1 s2 s3 s4 c1 c2 n 0)
    "enu2" => Just (enu2 s1 s2 s3 s4 c1 c2 n 0)
    "enu4" => Just (enu4 s1 s2 s3 s4 c1 c2 n 0)
    "enu8" => Just (enu8 s1 s2 s3 s4 c1 c2 n 0)
    "enu16" => Just (enu16 s1 s2 s3 s4 c1 c2 n 0)
    "enm2" => Just (enm2 s1 s2 s3 s4 c1 c2 n 0)
    "enm4" => Just (enm4 s1 s2 s3 s4 c1 c2 n 0)
    "enm8" => Just (enm8 s1 s2 s3 s4 c1 c2 n 0)
    "enm16" => Just (enm16 s1 s2 s3 s4 c1 c2 n 0)
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
