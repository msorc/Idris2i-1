import Data.Buffer
import Bytes

%default total

-- The sum of the bytes, read with the wrapper of another module.
sumBytes : Buffer -> (i : Int) -> (n : Int) -> Int -> Int
sumBytes b i n acc =
  if i >= n then acc
  else sumBytes b (assert_smaller i (i + 1)) n (acc + cast (byteAt b i))

fill : Buffer -> Int -> Int -> IO ()
fill b i n = if i >= n then pure () else do
  () <- setByte b i (cast (i * 7))
  fill b (assert_smaller i (i + 1)) n

main : IO ()
main = do
  Just b <- newBuffer 1000
    | Nothing => putStrLn "no buffer"
  fill b 0 1000
  printLn (sumBytes b 0 1000 0)
