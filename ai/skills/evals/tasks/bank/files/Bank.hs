module Main where

import qualified Data.Map as M
import Data.List (sortOn, foldl')
import Data.Maybe (fromMaybe)

data Kind = Deposit | Withdrawal deriving (Show, Eq)

data Tx = Tx { account :: String, kind :: Kind, amount :: Int } deriving Show

type Ledger = M.Map String Int

-- Apply one transaction, or say why it is refused.
apply :: Ledger -> Tx -> Either String Ledger
apply l (Tx acc k amt)
  | amt <= 0 = Left ("bad amount for " ++ acc)
  | k == Withdrawal && bal < amt = Left ("insufficient funds in " ++ acc)
  | otherwise = Right (M.insert acc (bal + delta) l)
  where
    bal = fromMaybe 0 (M.lookup acc l)
    delta = if k == Deposit then amt else negate amt

-- Apply all transactions in order; refused ones are reported and skipped.
run :: [Tx] -> (Ledger, [String])
run = foldl' step (M.empty, [])
  where
    step (l, errs) tx = case apply l tx of
      Left e -> (l, errs ++ [e])
      Right l' -> (l', errs)

-- "alice + 100" is a deposit, "alice - 30" a withdrawal.
parseTx :: String -> Maybe Tx
parseTx line = case words line of
  [acc, "+", n] -> Just (Tx acc Deposit (read n))
  [acc, "-", n] -> Just (Tx acc Withdrawal (read n))
  _ -> Nothing

-- Richest account first.
report :: Ledger -> [String]
report l = [name ++ ": " ++ show bal | (name, bal) <- sortOn (negate . snd) (M.toList l)]

main :: IO ()
main = do
  input <- getContents
  let txs = [t | Just t <- map parseTx (lines input)]
      (ledger, errs) = run txs
  mapM_ putStrLn (report ledger)
  mapM_ (putStrLn . ("error: " ++)) errs
  putStrLn ("total: " ++ show (sum (M.elems ledger)))
