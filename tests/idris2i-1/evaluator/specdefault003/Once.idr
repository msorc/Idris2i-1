module Once

-- Making the run time definition of main makes copies (with
-- --spec-interfaces), whose own run time definitions are made then: that
-- must not make the run time definitions of main, and of the copies made
-- before, again (it did, once for every copy).

total
sumBy : Num b => (a -> b) -> List a -> b
sumBy f [] = 0
sumBy f (x :: xs) = f x + sumBy f xs

total
maxOf : Ord a => a -> List a -> a
maxOf m [] = m
maxOf m (x :: xs) = maxOf (max m x) xs

main : IO ()
main = do printLn (sumBy (* 2) [1, 2, the Integer 3])
          printLn (maxOf 0 [3, 1, the Int 4])
          printLn (sumBy cast [1.5, the Double 2.5])
