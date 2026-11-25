||| Reuse sites whose cell is always shared, in the style of persistent
||| data: the loops keep the list or the record that they update, so the
||| cell that the update could take over is never unique, and every step
||| runs the arm that copies it.  `map` is a map over a list of 16 strings;
||| `setK` replaces a field of a record of K strings.
|||
||| Every line of the input is `CASE STEPS`, e.g. `set8 1000000`.
module Main

import Data.String

%default partial

%noinline
mapS : List String -> List String
mapS [] = []
mapS (x :: xs) = (if strLength x > 5 then "" else x) :: mapS xs

%noinline
firstLen : List String -> Int
firstLen (x :: _) = strLength x
firstLen [] = 0

data C1 = MkC1 String

%noinline
set1 : C1 -> C1
set1 (MkC1 a1) = MkC1 (if strLength a1 > 5 then "" else a1)

%noinline
len1 : C1 -> Int
len1 (MkC1 a1) = strLength a1

data C2 = MkC2 String String

%noinline
set2 : C2 -> C2
set2 (MkC2 a1 a2) = MkC2 (if strLength a1 > 5 then "" else a1) a2

%noinline
len2 : C2 -> Int
len2 (MkC2 a1 a2) = strLength a2

data C4 = MkC4 String String String String

%noinline
set4 : C4 -> C4
set4 (MkC4 a1 a2 a3 a4) = MkC4 (if strLength a1 > 5 then "" else a1) a2 a3 a4

%noinline
len4 : C4 -> Int
len4 (MkC4 a1 a2 a3 a4) = strLength a4

data C8 = MkC8 String String String String String String String String

%noinline
set8 : C8 -> C8
set8 (MkC8 a1 a2 a3 a4 a5 a6 a7 a8) = MkC8 (if strLength a1 > 5 then "" else a1) a2 a3 a4 a5 a6 a7 a8

%noinline
len8 : C8 -> Int
len8 (MkC8 a1 a2 a3 a4 a5 a6 a7 a8) = strLength a8

data C16 = MkC16 String String String String String String String String String String String String String String String String

%noinline
set16 : C16 -> C16
set16 (MkC16 a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16) = MkC16 (if strLength a1 > 5 then "" else a1) a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16

%noinline
len16 : C16 -> Int
len16 (MkC16 a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16) = strLength a16

loopMap : List String -> Int -> Int -> Int
loopMap xs 0 acc = acc
loopMap xs n acc = loopMap xs (n - 1) (acc + firstLen (mapS xs))

loop1 : C1 -> Int -> Int -> Int
loop1 r 0 acc = acc
loop1 r n acc = loop1 r (n - 1) (acc + len1 (set1 r))

loop2 : C2 -> Int -> Int -> Int
loop2 r 0 acc = acc
loop2 r n acc = loop2 r (n - 1) (acc + len2 (set2 r))

loop4 : C4 -> Int -> Int -> Int
loop4 r 0 acc = acc
loop4 r n acc = loop4 r (n - 1) (acc + len4 (set4 r))

loop8 : C8 -> Int -> Int -> Int
loop8 r 0 acc = acc
loop8 r n acc = loop8 r (n - 1) (acc + len8 (set8 r))

loop16 : C16 -> Int -> Int -> Int
loop16 r 0 acc = acc
loop16 r n acc = loop16 r (n - 1) (acc + len16 (set16 r))

runCase : String -> Int -> Maybe Int
runCase c n =
  let s1 = pack ['a', 'b']
      s2 = pack ['c', 'd']
      s3 = pack ['e', 'f']
      s4 = pack ['g', 'h'] in
  case c of
    "map" => Just (loopMap (concat (replicate 4 [s1, s2, s3, s4])) (n `div` 8) 0)
    "set1" => Just (loop1 (MkC1 s1) n 0)
    "set2" => Just (loop2 (MkC2 s1 s2) n 0)
    "set4" => Just (loop4 (MkC4 s1 s2 s3 s4) n 0)
    "set8" => Just (loop8 (MkC8 s1 s2 s3 s4 s1 s2 s3 s4) n 0)
    "set16" => Just (loop16 (MkC16 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4 s1 s2 s3 s4) n 0)
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
