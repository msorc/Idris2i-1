module Lib

public export
data T = A | B

public export
interface Pick a where
  partial
  pick : a -> a
  keep : a -> a

export
Pick T where
  pick A = B
  keep x = x

-- Generic functions: what they use of the dictionary is seen from their
-- definitions in the TTC
export
keepTwice : Pick a => a -> a
keepTwice x = keep (keep x)

export
pickOnce : Pick a => a -> a
pickOnce x = pick x

-- Covering (the default), and so accepted here
export
useKeep : T -> T
useKeep = keep

export
usePick : T -> T
usePick = pick

export
ints : Int -> List Int
ints n = [0 .. n]
