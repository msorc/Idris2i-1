-- expect: E1101
sign : Int -> Int
sign x | x > 0 = 1
       | otherwise = 0
