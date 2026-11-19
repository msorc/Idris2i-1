-- Default methods and superinterfaces
%default total

data T = A | B

-- A partial default method, which one implementation uses and another
-- overrides
interface Dflt a where
  partial
  dflt : a -> a
  dflt x = case the Bool True of
                True => x
  other : a -> a

Dflt T where
  other = id

Dflt Bool where
  dflt = not
  other = id

useDefault : T -> T
useDefault = dflt

useOverridden : Bool -> Bool
useOverridden = dflt

-- Not using the partial method does not help: the dictionary is partial
useOther : T -> T
useOther = other

-- A superinterface with a partial method
interface Base a where
  partial
  base : a -> a

interface Base a => Sub a where
  sub : a -> a

Base T where
  base A = B

Sub T where
  sub = id

viaParent : Sub a => a -> a
viaParent = base

useViaParent : T -> T
useViaParent = viaParent

useSub : T -> T
useSub = sub
