module Main

import Data.List
import Data.Vect

-- A branch that builds again the cell it matched (the same constructor, with
-- the fields it bound, in order) gives the cell itself, even when the types
-- differ: no uniqueness test, no copy, no new cell.

-- The bind of a monad of `Either`, as in `Core.>>=` of the compiler.
bindE : Either String a -> (a -> Either String b) -> Either String b
bindE (Left e) _ = Left e
bindE (Right x) f = f x

-- (a `do` block over it)
half : Int -> Either String Int
half x = if x `mod` 2 == 0 then Right (x `div` 2) else Left ("odd " ++ show x)

quarter : Int -> Either String Int
quarter x = half x `bindE` half

-- A rebuild that is a part of the result, not the whole of it.
withZero : Either String Int -> (Either String Bool, Nat)
withZero (Left e) = (Left e, 0)
withZero (Right n) = (Right (n > 0), 1)

-- Not rewritten: a field that the branch also uses elsewhere (the value
-- would stay alive through the branch, and the field need a reference).
withLength : Either String Int -> (Either String Bool, Nat)
withLength (Left e) = (Left e, length e)
withLength (Right n) = (Right (n > 0), 0)

-- Two fields.  (Each of these functions has another branch, or it would be
-- the identity, which the compiler sees already, see Compiler.Opts.Identity.)
idPair : Bool -> (String, List Int) -> (String, List Int)
idPair False _ = ("none", [])
idPair True (s, xs) = (s, xs)

-- Not rebuilds: another constructor of the same shape, the fields in
-- another order, a field replaced by another one.
swapE : Either String String -> Either String String
swapE (Left x) = Right x
swapE (Right x) = Left x

swapP : (String, String) -> (String, String)
swapP (x, y) = (y, x)

firstTwice : (String, String) -> (String, String)
firstTwice (x, y) = (x, x)

-- Nested matches: the inner cell is `t`, so the outer one is the argument.
keepTwo : List String -> List String
keepTwo (h :: t) = case t of
                     (h2 :: t2) => h :: (h2 :: t2)
                     [] => [h ++ "!"]
keepTwo [] = []

-- An erased field (the length of the vector) is not stored: the cell holds
-- the two others.
idVect : Bool -> Vect (S n) String -> Vect (S n) String
idVect False (_ :: xs) = "none" :: xs
idVect True (x :: xs) = x :: xs

-- A field of type `Type` (ω: stored, an erased value at run time): the
-- variable that the branch bound is a field like any other, but an erased
-- value written in the constructor is not taken for it.
data Box : Type where
  MkBox : (t : Type) -> String -> Box

reBox : Bool -> Box -> Box
reBox False _ = MkBox String "none"
reBox True (MkBox t s) = MkBox t s

boxNat : Box -> Box
boxNat (MkBox _ s) = MkBox Nat s

unBox : Box -> String
unBox (MkBox _ s) = s

-- Raw fields (two Doubles stored as C numbers in the cell): the same layout.
record Point where
  constructor MkPoint
  px : Double
  py : Double
  name : String

samePoint : Bool -> Point -> Point
samePoint False _ = MkPoint 0 0 "origin"
samePoint True (MkPoint x y n) = MkPoint x y n

flipPoint : Point -> Point
flipPoint (MkPoint x y n) = MkPoint y x n

-- A one-field record is a newtype: there is no cell.
record Wrap where
  constructor MkWrap
  unwrap : List Int

rewrap : Wrap -> Wrap
rewrap (MkWrap xs) = MkWrap xs

-- A list-like type of its own has the intrinsic constructors of `List`
-- (`_builtin.CONS`), unless a field is stored raw: then it keeps its own.
data Stack = Bottom | Push String Stack

pushAgain : Stack -> Stack
pushAgain Bottom = Push "bottom" Bottom
pushAgain (Push s r) = Push s r

top : Stack -> String
top Bottom = "none"
top (Push s _) = s

data Doubles = DNil | DCons Double Doubles

consAgain : Doubles -> Doubles
consAgain DNil = DCons 0 DNil
consAgain (DCons d r) = DCons d r

sumD : Doubles -> Double
sumD DNil = 0
sumD (DCons d r) = d + sumD r

-- A constructor without fields is static already.
noneAgain : Maybe Int -> Maybe String
noneAgain Nothing = Nothing
noneAgain (Just x) = Just (show x)

-- The scrutinee is a field of a parameter that the function would only
-- look at otherwise.
tailIfPositive : (List Int, Int) -> List Int
tailIfPositive (xs, n) = if n > 0 then (case xs of
                                          (y :: ys) => y :: ys
                                          [] => [])
                                  else Data.List.drop 1 xs

-- Not rewritten: the rebuild is in a `case` of the branch, whose other path
-- uses a field.
tailOr : List Int -> List Int
tailOr (y :: ys) = if y > 0 then y :: ys else ys
tailOr [] = []

main : IO ()
main = do
  printLn (quarter 12, quarter 6, quarter 7)
  -- the unique path and the shared one
  let shared = the (Either String Int) (Left ("shared " ++ show (the Int 1)))
  printLn (bindE shared (\x => Right (x + 1)), shared)
  printLn (bindE (Left ("fresh " ++ show (the Int 2))) (\x => Right (the Int x)))
  printLn (withLength (Left ("err" ++ show (the Int 3))), withLength (Right 4))
  printLn (withZero (Left ("err" ++ show (the Int 3))), withZero (Right 4))
  printLn (withZero shared, shared)
  printLn (withLength shared, shared)
  let p = ("p" ++ show (the Int 5), [1, 2, 3])
  printLn (idPair True p, p, idPair False p)
  printLn (idPair True ("q" ++ show (the Int 6), [4]))
  printLn (swapE (Left "a"), swapE (Right "b"))
  printLn (swapP ("x", "y"), firstTwice ("x", "y"))
  let l = ["a" ++ show (the Int 7), "b", "c"]
  printLn (keepTwo l, l)
  printLn (keepTwo ["d" ++ show (the Int 8), "e"], keepTwo ["f"], keepTwo [])
  let v = the (Vect 2 String) ["v" ++ show (the Int 9), "w"]
  printLn (idVect True v, v, idVect False v)
  printLn (unBox (reBox True (MkBox Int ("box" ++ show (the Int 10)))), unBox (boxNat (MkBox String "n")))
  let pt = MkPoint 1.5 2.5 ("pt" ++ show (the Int 11))
  let showPt = \q => (q.px, q.py, q.name)
  printLn (showPt (samePoint True pt), showPt (flipPoint pt), showPt pt)
  printLn (showPt (samePoint True (MkPoint 3.5 4.5 "fresh")), showPt (samePoint False pt))
  printLn (unwrap (rewrap (MkWrap [1, 2])))
  let st = Push ("top" ++ show (the Int 12)) Bottom
  printLn (top (pushAgain st), top (pushAgain Bottom), top st)
  let ds = DCons 1.25 (DCons 2.5 DNil)
  printLn (sumD (consAgain ds), sumD (consAgain DNil), sumD ds)
  printLn (noneAgain Nothing, noneAgain (Just 13))
  let xs = [14, 15]
  printLn (tailIfPositive (xs, 1), tailIfPositive (xs, 0), xs)
  printLn (tailOr xs, tailOr [-1, 2], xs)
