-- With --method-totality, covering functions count the methods of the
-- implementations they use too
%default covering

half : Int -> Int
half x = x `div` 2

-- Through another function
quarter : Int -> Int
quarter x = half (half x)

-- On Integer
seventh : Integer -> Integer
seventh n = n `mod` 7

partial
honest : Int -> Int
honest x = x `div` 2

asserted : Int -> Int
asserted x = assert_total $ x `div` 2 -- 2 is not zero
