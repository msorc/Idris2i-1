module Main

import Data.List
import Data.Map as M

data Grade = A | B | C | F deriving (Show, Eq)

record Student where
  constructor MkStudent
  name :: String
  scores :: List Int

average :: List Int -> Double
average [] = 0
average xs = fromIntegral (sum xs) / fromIntegral (length xs)

grade :: Double -> Grade
grade avg
  | avg >= 90 = A
  | avg >= 75 = B
  | avg >= 60 = C
  | otherwise = F

-- "Ada: 91.5 (A)"
describe :: Student -> String
describe s = name s ++ ": " ++ show avg ++ " (" ++ show (grade avg) ++ ")"
  where avg = average (scores s)

-- students with the best average first
ranking :: List Student -> List Student
ranking = sortOn (negate . average . scores)

-- how many students got each grade, keyed by the grade's name
histogram :: List Student -> M.Map String Int
histogram = foldr (\s -> M.insertWith (+) (show (grade (average (scores s)))) 1) M.empty

-- add bonus points to every score, capped at 100
curve :: Int -> Student -> Student
curve bonus s = s { scores = map (\x -> min 100 (x + bonus)) (scores s) }

students :: List Student
students =
  [ MkStudent "Ada" [95, 88]
  , MkStudent "Brook" [70, 65, 81]
  , MkStudent "Cy" []
  , MkStudent "Dee" [59, 61]
  ]

main :: IO ()
main = do
  mapM_ (putStrLn . describe) (ranking students)
  putStrLn "--- curved by 10"
  mapM_ (putStrLn . describe) (ranking (map (curve 10) students))
  putStrLn "--- grades"
  forM_ (M.toList (histogram students)) $ \(g, n) ->
    putStrLn (g ++ ": " ++ show n)
  print (length students)
