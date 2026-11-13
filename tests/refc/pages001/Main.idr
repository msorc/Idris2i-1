-- Pages that a size class empties are reused by another one: the peak is
-- about the size of one phase, not of both.

data Small = SEnd | SLink Int Small

-- 7 fields: 64 bytes, where SLink takes 24
data Big = BEnd | BLink Int Int Int Int Int Int Big

mkSmall : Small -> Int -> Small
mkSmall acc 0 = acc
mkSmall acc n = mkSmall (SLink n acc) (n - 1)

sumSmall : Int -> Small -> Int
sumSmall acc SEnd = acc
sumSmall acc (SLink x r) = sumSmall (acc + x) r

mkBig : Big -> Int -> Big
mkBig acc 0 = acc
mkBig acc n = mkBig (BLink n n n n n n acc) (n - 1)

sumBig : Int -> Big -> Int
sumBig acc BEnd = acc
sumBig acc (BLink x _ _ _ _ _ r) = sumBig (acc + x) r

main : IO ()
main = do
  -- 48MB of small cells, then 48MB of big ones
  printLn (sumSmall 0 (mkSmall SEnd 2000000))
  printLn (sumBig 0 (mkBig BEnd 750000))
