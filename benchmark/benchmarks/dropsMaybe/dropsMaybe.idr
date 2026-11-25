||| The `Nothing` arm of an inlined bind of `Maybe` as the hot path.
|||
||| As dropsEither, with `Maybe`: the arm releases the captured values and
||| gives `Nothing`, a nullary constructor (no cell).  The cases are named
||| as there, with `m` for `e`.  Every line of the input is `CASE STEPS`,
||| e.g. `mtb8 1000000`.
module Main

import Data.String

%default partial

-- Fails at every call: the counters are never negative.
%noinline
check : Int -> Maybe Int
check i = if i >= 0 then Nothing else Just (i + 1)

%inline
bind : Maybe a -> (a -> Maybe b) -> Maybe b
bind Nothing _ = Nothing
bind (Just x) k = k x

%noinline
finish : Maybe b -> Maybe b
finish r = r

data T2 a1 a2 = MkT2 a1 a2

data T4 a1 a2 a3 a4 = MkT4 a1 a2 a3 a4

data T8 a1 a2 a3 a4 a5 a6 a7 a8 = MkT8 a1 a2 a3 a4 a5 a6 a7 a8

data T16 a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16 = MkT16 a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16

%noinline
e2 : Int -> a1 -> a2 -> Maybe (T2 a1 a2)
e2 i v1 v2 = check i `bind` \x => Just (MkT2 v1 v2)

%noinline
n2 : Int -> a1 -> a2 -> Maybe (T2 a1 a2)
n2 i v1 v2 = finish (check i `bind` \x => Just (MkT2 v1 v2))

%noinline
e4 : Int -> a1 -> a2 -> a3 -> a4 -> Maybe (T4 a1 a2 a3 a4)
e4 i v1 v2 v3 v4 = check i `bind` \x => Just (MkT4 v1 v2 v3 v4)

%noinline
n4 : Int -> a1 -> a2 -> a3 -> a4 -> Maybe (T4 a1 a2 a3 a4)
n4 i v1 v2 v3 v4 = finish (check i `bind` \x => Just (MkT4 v1 v2 v3 v4))

%noinline
e8 : Int -> a1 -> a2 -> a3 -> a4 -> a5 -> a6 -> a7 -> a8 -> Maybe (T8 a1 a2 a3 a4 a5 a6 a7 a8)
e8 i v1 v2 v3 v4 v5 v6 v7 v8 = check i `bind` \x => Just (MkT8 v1 v2 v3 v4 v5 v6 v7 v8)

%noinline
n8 : Int -> a1 -> a2 -> a3 -> a4 -> a5 -> a6 -> a7 -> a8 -> Maybe (T8 a1 a2 a3 a4 a5 a6 a7 a8)
n8 i v1 v2 v3 v4 v5 v6 v7 v8 = finish (check i `bind` \x => Just (MkT8 v1 v2 v3 v4 v5 v6 v7 v8))

%noinline
e16 : Int -> a1 -> a2 -> a3 -> a4 -> a5 -> a6 -> a7 -> a8 -> a9 -> a10 -> a11 -> a12 -> a13 -> a14 -> a15 -> a16 -> Maybe (T16 a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16)
e16 i v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 v16 = check i `bind` \x => Just (MkT16 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 v16)

%noinline
n16 : Int -> a1 -> a2 -> a3 -> a4 -> a5 -> a6 -> a7 -> a8 -> a9 -> a10 -> a11 -> a12 -> a13 -> a14 -> a15 -> a16 -> Maybe (T16 a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16)
n16 i v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 v16 = finish (check i `bind` \x => Just (MkT16 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 v16))

mtb2 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mtb2 s1 s2 s3 s4 c1 c2 0 acc = acc
mtb2 s1 s2 s3 s4 c1 c2 n acc = case e2 n s1 s2 of
  Nothing => mtb2 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mtb4 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mtb4 s1 s2 s3 s4 c1 c2 0 acc = acc
mtb4 s1 s2 s3 s4 c1 c2 n acc = case e4 n s1 s2 s3 s4 of
  Nothing => mtb4 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mtb8 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mtb8 s1 s2 s3 s4 c1 c2 0 acc = acc
mtb8 s1 s2 s3 s4 c1 c2 n acc = case e8 n s1 s2 s3 s4 s1 s2 s3 s4 of
  Nothing => mtb8 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mtb16 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mtb16 s1 s2 s3 s4 c1 c2 0 acc = acc
mtb16 s1 s2 s3 s4 c1 c2 n acc = case e16 n s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4 of
  Nothing => mtb16 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mtu2 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mtu2 s1 s2 s3 s4 c1 c2 0 acc = acc
mtu2 s1 s2 s3 s4 c1 c2 n acc = case e2 n c1 c2 of
  Nothing => mtu2 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mtu4 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mtu4 s1 s2 s3 s4 c1 c2 0 acc = acc
mtu4 s1 s2 s3 s4 c1 c2 n acc = case e4 n c1 c2 c1 c2 of
  Nothing => mtu4 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mtu8 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mtu8 s1 s2 s3 s4 c1 c2 0 acc = acc
mtu8 s1 s2 s3 s4 c1 c2 n acc = case e8 n c1 c2 c1 c2 c1 c2 c1 c2 of
  Nothing => mtu8 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mtu16 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mtu16 s1 s2 s3 s4 c1 c2 0 acc = acc
mtu16 s1 s2 s3 s4 c1 c2 n acc = case e16 n c1 c2 c1 c2 c1 c2 c1 c2 c1 c2 c1 c2 c1 c2 c1 c2 of
  Nothing => mtu16 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mtm2 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mtm2 s1 s2 s3 s4 c1 c2 0 acc = acc
mtm2 s1 s2 s3 s4 c1 c2 n acc = case e2 n s1 c1 of
  Nothing => mtm2 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mtm4 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mtm4 s1 s2 s3 s4 c1 c2 0 acc = acc
mtm4 s1 s2 s3 s4 c1 c2 n acc = case e4 n s1 c1 "lit" [n] of
  Nothing => mtm4 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mtm8 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mtm8 s1 s2 s3 s4 c1 c2 0 acc = acc
mtm8 s1 s2 s3 s4 c1 c2 n acc = case e8 n s1 c1 "lit" [n] s2 c1 "lit" [n] of
  Nothing => mtm8 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mtm16 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mtm16 s1 s2 s3 s4 c1 c2 0 acc = acc
mtm16 s1 s2 s3 s4 c1 c2 n acc = case e16 n s1 c1 "lit" [n] s2 c1 "lit" [n] s3 c1 "lit" [n] s4 c1 "lit" [n] of
  Nothing => mtm16 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mnb2 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mnb2 s1 s2 s3 s4 c1 c2 0 acc = acc
mnb2 s1 s2 s3 s4 c1 c2 n acc = case n2 n s1 s2 of
  Nothing => mnb2 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mnb4 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mnb4 s1 s2 s3 s4 c1 c2 0 acc = acc
mnb4 s1 s2 s3 s4 c1 c2 n acc = case n4 n s1 s2 s3 s4 of
  Nothing => mnb4 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mnb8 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mnb8 s1 s2 s3 s4 c1 c2 0 acc = acc
mnb8 s1 s2 s3 s4 c1 c2 n acc = case n8 n s1 s2 s3 s4 s1 s2 s3 s4 of
  Nothing => mnb8 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mnb16 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mnb16 s1 s2 s3 s4 c1 c2 0 acc = acc
mnb16 s1 s2 s3 s4 c1 c2 n acc = case n16 n s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4 of
  Nothing => mnb16 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mnu2 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mnu2 s1 s2 s3 s4 c1 c2 0 acc = acc
mnu2 s1 s2 s3 s4 c1 c2 n acc = case n2 n c1 c2 of
  Nothing => mnu2 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mnu4 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mnu4 s1 s2 s3 s4 c1 c2 0 acc = acc
mnu4 s1 s2 s3 s4 c1 c2 n acc = case n4 n c1 c2 c1 c2 of
  Nothing => mnu4 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mnu8 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mnu8 s1 s2 s3 s4 c1 c2 0 acc = acc
mnu8 s1 s2 s3 s4 c1 c2 n acc = case n8 n c1 c2 c1 c2 c1 c2 c1 c2 of
  Nothing => mnu8 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mnu16 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mnu16 s1 s2 s3 s4 c1 c2 0 acc = acc
mnu16 s1 s2 s3 s4 c1 c2 n acc = case n16 n c1 c2 c1 c2 c1 c2 c1 c2 c1 c2 c1 c2 c1 c2 c1 c2 of
  Nothing => mnu16 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mnm2 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mnm2 s1 s2 s3 s4 c1 c2 0 acc = acc
mnm2 s1 s2 s3 s4 c1 c2 n acc = case n2 n s1 c1 of
  Nothing => mnm2 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mnm4 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mnm4 s1 s2 s3 s4 c1 c2 0 acc = acc
mnm4 s1 s2 s3 s4 c1 c2 n acc = case n4 n s1 c1 "lit" [n] of
  Nothing => mnm4 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mnm8 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mnm8 s1 s2 s3 s4 c1 c2 0 acc = acc
mnm8 s1 s2 s3 s4 c1 c2 n acc = case n8 n s1 c1 "lit" [n] s2 c1 "lit" [n] of
  Nothing => mnm8 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

mnm16 : String -> String -> String -> String -> Char -> Char -> Int -> Int -> Int
mnm16 s1 s2 s3 s4 c1 c2 0 acc = acc
mnm16 s1 s2 s3 s4 c1 c2 n acc = case n16 n s1 c1 "lit" [n] s2 c1 "lit" [n] s3 c1 "lit" [n] s4 c1 "lit" [n] of
  Nothing => mnm16 s1 s2 s3 s4 c1 c2 (n - 1) (acc + 1)
  Just _ => acc

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
    "mtb2" => Just (mtb2 s1 s2 s3 s4 c1 c2 n 0)
    "mtb4" => Just (mtb4 s1 s2 s3 s4 c1 c2 n 0)
    "mtb8" => Just (mtb8 s1 s2 s3 s4 c1 c2 n 0)
    "mtb16" => Just (mtb16 s1 s2 s3 s4 c1 c2 n 0)
    "mtu2" => Just (mtu2 s1 s2 s3 s4 c1 c2 n 0)
    "mtu4" => Just (mtu4 s1 s2 s3 s4 c1 c2 n 0)
    "mtu8" => Just (mtu8 s1 s2 s3 s4 c1 c2 n 0)
    "mtu16" => Just (mtu16 s1 s2 s3 s4 c1 c2 n 0)
    "mtm2" => Just (mtm2 s1 s2 s3 s4 c1 c2 n 0)
    "mtm4" => Just (mtm4 s1 s2 s3 s4 c1 c2 n 0)
    "mtm8" => Just (mtm8 s1 s2 s3 s4 c1 c2 n 0)
    "mtm16" => Just (mtm16 s1 s2 s3 s4 c1 c2 n 0)
    "mnb2" => Just (mnb2 s1 s2 s3 s4 c1 c2 n 0)
    "mnb4" => Just (mnb4 s1 s2 s3 s4 c1 c2 n 0)
    "mnb8" => Just (mnb8 s1 s2 s3 s4 c1 c2 n 0)
    "mnb16" => Just (mnb16 s1 s2 s3 s4 c1 c2 n 0)
    "mnu2" => Just (mnu2 s1 s2 s3 s4 c1 c2 n 0)
    "mnu4" => Just (mnu4 s1 s2 s3 s4 c1 c2 n 0)
    "mnu8" => Just (mnu8 s1 s2 s3 s4 c1 c2 n 0)
    "mnu16" => Just (mnu16 s1 s2 s3 s4 c1 c2 n 0)
    "mnm2" => Just (mnm2 s1 s2 s3 s4 c1 c2 n 0)
    "mnm4" => Just (mnm4 s1 s2 s3 s4 c1 c2 n 0)
    "mnm8" => Just (mnm8 s1 s2 s3 s4 c1 c2 n 0)
    "mnm16" => Just (mnm16 s1 s2 s3 s4 c1 c2 n 0)
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
