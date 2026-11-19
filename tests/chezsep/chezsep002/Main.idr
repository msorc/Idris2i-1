module Main

import Data.IORef
import Data.List
import Data.SortedMap
import Geometry.Shape
import Geometry.Table
import Util.Text

main : IO ()
main = do
  let shapes = [Circle 2, Rect 3 4, Tri 6 5, Rect 1 1, Circle 1]
  let table = areas shapes
  count <- newIORef (the Nat 0)
  for_ (SortedMap.toList table) $ \(n, a) => do
    modifyIORef count (+ 1)
    putStrLn (pad 10 n ++ ": " ++ pad 3 (show a))
  putStrLn ("total " ++ show (grandTotal table))
  putStrLn ("kinds " ++ show !(readIORef count))
  putStrLn (commas (sort (map name shapes)))
