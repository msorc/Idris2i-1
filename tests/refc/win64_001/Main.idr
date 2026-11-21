-- Calls in tail position between functions of different arities, and to
-- closures, which may be jumps (see IDRIS2_MUSTTAIL in runtime.h).
mutual
  f1 : Int -> Int
  f1 n = if n <= 0 then 0 else f4 (n - 1) n 1 2

  f4 : Int -> Int -> Int -> Int -> Int
  f4 n a b c = if n <= 0 then a + b + c else f6 (n - 1) a b c 3 4

  f6 : Int -> Int -> Int -> Int -> Int -> Int -> Int
  f6 n a b c d e = if n <= 0 then a + b + c + d + e else f1 (n - 1)

apply5 : (Int -> Int -> Int -> Int -> Int -> Int) -> Int -> Int
apply5 f n = f n 1 2 3 4

apply6 : (Int -> Int -> Int -> Int -> Int -> Int -> Int) -> Int -> Int
apply6 f n = f n 1 2 3 4 5

main : IO ()
main = do
  printLn (f1 1000000)
  printLn (apply5 (\a, b, c, d, e => a + b * c + d * e) 10)
  printLn (apply6 (\a, b, c, d, e, g => a * b + c * d + e * g) 10)
