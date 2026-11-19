module Main

-- traverse and friends on lists in Control.App, which the library runs as
-- loops (as the browser backend needs, see tests/node/applchain_browser), with
-- the results and the order of the effects of the chains of <*> and *>.

import Control.App
import Data.List

%default covering

xs : List Integer
xs = [1 .. 100000]

step : PrimIO es => Integer -> App es Integer
step x = pure (x * 2)

say : PrimIO es => Integer -> App es Integer
say x = do primIO (putStrLn ("app " ++ show x)); pure x

data Stop = MkStop Integer

stop : Has [Exception Stop] es => PrimIO es => Integer -> App es Integer
stop x = do primIO (putStrLn ("stop " ++ show x))
            if x == 2 then throw (MkStop x) else pure x

small : List Integer
small = [1, 2, 3]

long : App Init ()
long = do
  ys <- traverse step xs
  primIO $ putStrLn ("App traverse: " ++ show (sum ys))
  ys <- for xs step
  primIO $ putStrLn ("App for: " ++ show (sum ys))
  ys <- sequence (map step xs)
  primIO $ putStrLn ("App sequence: " ++ show (sum ys))
  traverse_ step xs
  for_ xs step
  sequence_ (map step xs)
  primIO $ putStrLn "App traverse_, for_, sequence_"

order : App Init ()
order = do
  ys <- traverse say small
  primIO $ putStrLn ("App order: " ++ show ys)
  traverse_ say small

exceptions : App Init ()
exceptions = do
  handle (traverse stop small)
         (\ys => primIO $ putStrLn ("App no exception: " ++ show ys))
         (\(MkStop x) => primIO $ putStrLn ("App exception: " ++ show x))
  handle (traverse_ stop small)
         (\() => primIO $ putStrLn "App no exception")
         (\(MkStop x) => primIO $ putStrLn ("App exception: " ++ show x))

main : IO ()
main = do
  run long
  run order
  run exceptions
