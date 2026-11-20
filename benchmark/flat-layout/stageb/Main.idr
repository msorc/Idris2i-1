module Main

import Hint

mk : {auto l : Layout t} -> Int -> (Arr t -> r) -> r
mk {l} n k = k (MkArr (describe l) [])

useDouble : Arr Double -> String
useDouble a = a.layoutName

-- 1. t is known only from the continuation, elaborated after the implicit.
t1 : String
t1 = mk 3 (\a => useDouble a)

-- 2. t known at the call.
t2 : String
t2 = mk {t = Double} 3 (\a => a.layoutName)

-- 3. Maybe Double, known later.
useMD : Arr (Maybe Double) -> String
useMD a = a.layoutName
t3 : String
t3 = mk 3 (\a => useMD a)

-- 4. Generic code without the constraint: the default.
gen2 : {0 e : Type} -> Int -> (Arr e -> String) -> String
gen2 n k = mk n (\a => k a)

-- 5. Generic code with the constraint passes it on.
gen3 : {auto l : Layout e} -> Int -> (Arr e -> String) -> String
gen3 n k = mk n (\a => k a)

-- 6. t solved by a later statement of a do block.
t6 : IO String
t6 = do let s = mk 3 (\a => a.layoutName ++ show (length (the (List Double) a.elems)))
        pure s

main : IO ()
main = do
  printLn [t1, t2, t3, gen2 3 useDouble, gen3 3 useDouble]
  putStrLn !t6
