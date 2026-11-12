module DivMod

-- `div` and `mod` are Euclidean: `mod` is never negative, and
-- `(x `div` y) * y + (x `mod` y) == x`.  The divisors are either known
-- constants (which the C compiler can turn into shifts) or values computed at
-- run time.

pairs : List (Integer, Integer)
pairs =
  [ (-4, 2), (4, 2), (-5, 2), (5, 2), (-4, -2), (4, -2), (-5, -2), (5, -2)
  , (-34, 17), (-35, 17), (34, -17), (-34, -17), (0, 3), (0, -3)
  , (-1, 1), (-1, 100), (99, 100), (-100, 100), (-101, 100), (127, -1)
  ]

both : (Show a, Integral a) => (Integer -> a) -> String
both from = show [ (x `div` y, x `mod` y) | (a, b) <- pairs, let x = from a, let y = from b ]

dm : Integral a => a -> a -> (a, a)
dm x y = (x `div` y, x `mod` y)

halves : (Show a, Integral a, Neg a) => (Integer -> a) -> String
halves from =
  show [ (dm x 2, dm x (-4), dm x 17) | (a, _) <- pairs, let x = from a ]

main : IO ()
main = do
  putStrLn $ "Int8    " ++ both (cast {to = Int8})
  putStrLn $ "Int16   " ++ both (cast {to = Int16})
  putStrLn $ "Int32   " ++ both (cast {to = Int32})
  putStrLn $ "Int64   " ++ both (cast {to = Int64})
  putStrLn $ "Int     " ++ both (cast {to = Int})
  putStrLn $ "Integer " ++ both id
  putStrLn $ "Int8    " ++ halves (cast {to = Int8})
  putStrLn $ "Int16   " ++ halves (cast {to = Int16})
  putStrLn $ "Int32   " ++ halves (cast {to = Int32})
  putStrLn $ "Int64   " ++ halves (cast {to = Int64})
  putStrLn $ "Int     " ++ halves (cast {to = Int})
  putStrLn $ "Integer " ++ halves id
  -- beyond 32 bits (boxed values) and beyond 64 bits (GMP)
  putStrLn $ show [ (x `div` y, x `mod` y)
                  | x <- the (List Int) [-6000000000, 6000000000, -12884901888]
                  , y <- [2, -3, 4294967296] ]
  putStrLn $ show [ (x `div` y, x `mod` y)
                  | x <- [-100000000000000000000, 100000000000000000001]
                  , y <- the (List Integer) [2, -7, 10000000000] ]
