-- The method totality check is per method: a total function may use an
-- implementation with methods that are not covering, as long as it may only
-- use its covering methods.
%default total

-- Ranges of Int and Integer take `Integral` (in a constraint tuple), but use
-- none of its methods
rangeInt : Int -> List Int
rangeInt n = [0 .. n]

rangeInteger : Integer -> Integer -> List Integer
rangeInteger x y = [x, x + 2 .. y]

rangeFrom : Int -> List Int
rangeFrom x = take 3 [x ..]

rangeChar : List Char
rangeChar = ['a' .. 'z']

rangeBits : Bits8 -> List Bits8
rangeBits x = [x .. 10]

-- `div` and `mod` themselves are still not covering
divInt : Int -> Int -> Int
divInt x y = x `div` y

modInteger : Integer -> Integer
modInteger x = x `mod` 3

-- `+` through the `Num` parent of `Integral`
plus : Integral a => a -> a -> a
plus x y = x + y

plusInt : Int -> Int
plusInt x = plus x 1

-- ... but not `div` through a function that uses it
half : Integral a => a -> a
half x = x `div` 2

halfInt : Int -> Int
halfInt = half

-- Through two functions
plus2 : Integral a => a -> a
plus2 x = plus x (plus x x)

plus2Int : Int -> Int
plus2Int = plus2

half2 : Integral a => a -> a
half2 x = plus (half x) x

half2Int : Int -> Int
half2Int = half2

-- A user interface with a partial method and a total one
data T = A | B

interface Pick a where
  partial
  pick : a -> a
  keep : a -> a

Pick T where
  pick A = B
  keep x = x

useKeep : T -> T
useKeep = keep

usePick : T -> T
usePick = pick

-- The dictionary passed through functions which use only `keep`
keepTwice : Pick a => a -> a
keepTwice x = keep (keep x)

viaKeepTwice : T -> T
viaKeepTwice = keepTwice

-- In a constraint tuple
Eq T where
  A == A = True
  B == B = True
  _ == _ = False

both : (Pick a, Eq a) => a -> Bool
both x = keep x == x

useBoth : T -> Bool
useBoth = both

pickBoth : (Pick a, Eq a) => a -> Bool
pickBoth x = pick x == x

usePickBoth : T -> Bool
usePickBoth = pickBoth

-- Stored in a data structure: what is done with it is not followed, so all
-- of it counts
record Box a where
  constructor MkBox
  {auto dict : Pick a}
  val : a

boxed : Box T
boxed = MkBox A

unboxed : T
unboxed = let b = MkBox A in keep @{b.dict} b.val

-- A default method that uses a partial one, and another that uses only a
-- total one
interface Dflt a where
  partial
  risky : a -> a
  safe : a -> a
  viaRisky : a -> a
  viaRisky x = risky x
  viaSafe : a -> a
  viaSafe x = safe (safe x)

Dflt T where
  risky A = B
  safe x = x

useViaSafe : T -> T
useViaSafe = viaSafe

useViaRisky : T -> T
useViaRisky = viaRisky

-- A method defined by another method of the same implementation
interface Sib a where
  partial
  sibRisky : a -> a
  sibSafe : a -> a
  sibUses : a -> a

Sib T where
  sibUses x = sibRisky x
  sibRisky A = B
  sibSafe x = x

useSibSafe : T -> T
useSibSafe = sibSafe

useSibUses : T -> T
useSibUses = sibUses

-- A parent with a partial method, which the child's methods do not use
interface Base a where
  partial
  base : a -> a

interface Base a => Sub a where
  sub : a -> a

Base T where
  base A = B

Sub T where
  sub x = x

useSub : T -> T
useSub = sub

viaParent : Sub a => a -> a
viaParent = base

useViaParent : T -> T
useViaParent = viaParent

-- Named implementations
[partialNamed] Pick Nat where
  pick Z = Z
  keep x = x

useNamedKeep : Nat -> Nat
useNamedKeep = keep @{partialNamed}

useNamedPick : Nat -> Nat
useNamedPick = pick @{partialNamed}

-- An implementation built from another: `Show (List a)` from `Show a`
interface Desc a where
  partial
  desc : a -> String
  name : a -> String

Desc T where
  desc A = "A"
  name _ = "T"

Desc a => Desc (List a) where
  desc xs = concatMap desc xs
  name xs = "List"

useListName : List T -> String
useListName = name

useListDesc : List T -> String
useListDesc = desc

-- A method that is not a function is evaluated with the implementation, so
-- it counts whichever method is used
interface Konst a where
  partial
  konst : a
  ident : a -> a

Konst T where
  konst = case the Bool True of
               True => A
  ident x = x

useIdent : T -> T
useIdent = ident
