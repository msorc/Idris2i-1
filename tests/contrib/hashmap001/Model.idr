||| A model-based test: HashMap against SortedMap.
module Model

import Data.Hashable
import Data.HashMap
import Data.List
import Data.Nat
import Data.SortedMap
import Data.String

import Keys

next : Bits64 -> Bits64
next x = x * 6364136223846793005 + 1442695040888963407

pick : Bits64 -> Int -> Int
pick st bound = cast ((st `div` 65536) `mod` cast bound)

public export
record Model k where
  constructor MkModel
  hm : HashMap k Int
  sm : SortedMap Int Int

sameContents : Hashable k => (Int -> k) -> HashMap k Int -> SortedMap Int Int -> Bool
sameContents mk h s =
  size h == length (Data.SortedMap.keys s)
  && all (\(i, v) => lookup (mk i) h == Just v) (Data.SortedMap.toList s)
  && sort (map snd (Data.HashMap.toList h)) == sort (Data.SortedMap.values s)

step : Hashable k => (Int -> k) -> Bits64 -> Model k -> (Bits64, Model k)
step mk st (MkModel h s) =
  let st1 = next st
      st2 = next st1
      st3 = next st2
      op = pick st1 10
      key = pick st2 300
      val = pick st3 1000
  in (st3, case op of
        0 => MkModel (delete (mk key) h) (delete key s)
        1 => MkModel (delete (mk key) h) (delete key s)
        2 => MkModel (insertWith (+) (mk key) val h) (insertWith (+) key val s)
        3 => MkModel (update (map (+ 1)) (mk key) h) (update (map (+ 1)) key s)
        4 => MkModel (update (const (Just val)) (mk key) h) (update (const (Just val)) key s)
        _ => MkModel (insert (mk key) val h) (insert key val s))

runModel : Hashable k => String -> (Int -> k) -> IO ()
runModel name mk = go 5000 0x123456789 (MkModel empty empty) True 0
  where
    go : Nat -> Bits64 -> Model k -> Bool -> Int -> IO ()
    go Z _ (MkModel h s) ok checks =
      check ("model " ++ name ++ " (" ++ show checks ++ " comparisons, final size "
             ++ show (size h) ++ ")") (ok && sameContents mk h s)
    go (S n) st m ok checks =
      let (st', m') = step mk st m
          -- after every 250th operation compare everything
          full = modNatNZ n 250 ItIsSucc == 0
          ok' = ok && (not full || sameContents mk m'.hm m'.sm)
          -- always compare one key
          key = pick (next st') 300
          one = lookup (mk key) m'.hm == lookup key m'.sm
      in go n st' m' (ok' && one) (if full then checks + 1 else checks)

export
modelTests : IO ()
modelTests = do
  putStrLn "-- model against SortedMap"
  runModel "Int" id
  runModel "String" (\i => "key" ++ show i)
  runModel "same hash" MkSame
  runModel "few hashes" MkFew
  runModel "high bits" MkHigh
  runModel "pair" (\i => (i `div` 20, i `mod` 20))

