module Shadow

-- The local function show' of `Show (List a)` takes the `xs` of `show` and
-- has its own pattern variable `xs`: its copy for `Show Integer` is made
-- (it used to fail with "Non linear pattern variable").

total
countBelow : Ord a => a -> List a -> Nat
countBelow y xs = go 0 xs
  where
    go : Nat -> List a -> Nat
    go acc [] = acc
    go acc (x :: xs) = go (if x < y then S acc else acc) xs

main : IO ()
main = do printLn [1, 2, the Integer 3]
          printLn (countBelow 3 [1, 2, the Integer 3, 4, 1])
