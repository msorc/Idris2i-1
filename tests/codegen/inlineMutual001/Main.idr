module Main

-- Small mutually recursive functions: the inlining heuristic must not mark
-- them all for inlining, or every round of transformations (and every module
-- that inlines them) unrolls the recursion again, doubling the code.

mutual
  public export
  data Odd a b = OCons a (Even b a)

  public export
  data Even a b = ENil | ECons a (Odd b a)

mutual
  public export
  lenO : Odd a b -> Nat
  lenO (OCons x xs) = S (lenE xs)

  public export
  lenE : Even a b -> Nat
  lenE ENil = Z
  lenE (ECons x xs) = S (lenO xs)

mk : Nat -> Odd Nat String
mk Z = OCons 0 ENil
mk (S k) = OCons k (ECons (show k) (mk k))

main : IO ()
main = do
  n <- getLine
  printLn (lenO (mk (length n)))
  printLn (lenE (ECons "x" (mk (length n))))
