||| A list with linear fields, and list functions each written once, then
||| used by a linear client (the list, and the functions passed, are linear)
||| and by an unrestricted one (the list is used many times, the functions
||| passed are ordinary).  `failing` blocks show where one copy is not
||| enough.  The table in the commit that added this file sums it up.
module LList

import Data.List

%default total

-- The functions below are called `l<name of the Prelude's function>`: with
-- the same names they would be ambiguous with the Prelude's (that there is
-- no `Foldable LList` does not rule out the Prelude's `lsum`), and a `case`
-- on an ambiguous application is not retried at quantity 1.

public export
data LList : Type -> Type where
  Nil  : LList a
  (::) : (1 x : a) -> (1 xs : LList a) -> LList a

||| A linear Maybe
public export
data LMaybe : Type -> Type where
  None : LMaybe a
  Some : (1 x : a) -> LMaybe a

------------------------------------------------------------------------------
-- An unrestricted list with linear fields behaves like `List`: matching it
-- binds unrestricted pattern variables, and its constructors take
-- unrestricted values.

dupHeads : LList a -> LList a
dupHeads [] = []
dupHeads (x :: xs) = x :: x :: dupHeads xs

pairUp : LPair a b -> (a, a, b)
pairUp (x # y) = (x, x, y)

caseUse : LList Nat -> Nat
caseUse xs = case xs of
                  [] => 0
                  (y :: ys) => y + y

letUse : LPair Nat Nat -> Nat
letUse p = let (x # y) = p in x + x + y

-- At 1 the same match binds linear variables
failing "There are 2 uses of linear name x"
  dupLin : (1 _ : LList a) -> LList a
  dupLin [] = []
  dupLin (x :: xs) = x :: x :: dupLin xs

------------------------------------------------------------------------------
-- Written once, usable both ways: structural functions that neither drop
-- nor copy an element and take no function

lappend : (1 xs : LList a) -> (1 ys : LList a) -> LList a
lappend [] ys = ys
lappend (x :: xs) ys = x :: lappend xs ys

lrevOnto : (1 acc : LList a) -> (1 xs : LList a) -> LList a
lrevOnto acc [] = acc
lrevOnto acc (x :: xs) = lrevOnto (x :: acc) xs

lreverse : (1 xs : LList a) -> LList a
lreverse = lrevOnto []

lconcat : (1 xss : LList (LList a)) -> LList a
lconcat [] = []
lconcat (xs :: xss) = lappend xs (lconcat xss)

luncons : (1 xs : LList a) -> LMaybe (LPair a (LList a))
luncons [] = None
luncons (x :: xs) = Some (x # xs)

-- The separator is copied, so it is unrestricted; the list is linear
lintersperse : a -> (1 xs : LList a) -> LList a
lintersperse sep [] = []
lintersperse sep [x] = [x]
lintersperse sep (x :: y :: ys) = x :: sep :: lintersperse sep (y :: ys)

-- The element is copied, so it is unrestricted (a linear value can't be
-- replicated at all)
lreplicate : Nat -> a -> LList a
lreplicate Z _ = []
lreplicate (S k) x = x :: lreplicate k x

-- `take` and `drop` would drop elements: one function that returns both
-- parts serves both
lsplitAt : Nat -> (1 xs : LList a) -> LPair (LList a) (LList a)
lsplitAt Z xs = [] # xs
lsplitAt (S k) [] = [] # []
lsplitAt (S k) (x :: xs) = case lsplitAt k xs of
                                 (ys # zs) => (x :: ys) # zs

-- `length` would drop the elements: `llength` gives the list back.  `Res` has
-- an unrestricted first field.
llength : (1 xs : LList a) -> Res Nat (const (LList a))
llength [] = 0 # []
llength (x :: xs) = case llength xs of
                          (n # xs') => S n # (x :: xs')

------------------------------------------------------------------------------
-- Higher-order functions: the function argument's quantity has to be fixed.
-- With a linear argument, the linear client works and an unrestricted
-- function can't be passed (that would be omega becoming 1); with an
-- unrestricted argument, the elements of a linear list can't be passed to
-- it.  One copy per quantity (or a quantity variable).

lmap : ((1 _ : a) -> b) -> (1 xs : LList a) -> LList b
lmap f [] = []
lmap f (x :: xs) = f x :: lmap f xs

lfoldr : ((1 _ : a) -> (1 _ : b) -> b) -> (1 z : b) -> (1 xs : LList a) -> b
lfoldr f z [] = z
lfoldr f z (x :: xs) = f x (lfoldr f z xs)

lfoldl : ((1 _ : b) -> (1 _ : a) -> b) -> (1 z : b) -> (1 xs : LList a) -> b
lfoldl f z [] = z
lfoldl f z (x :: xs) = lfoldl f (f z x) xs

-- Uneven lists would drop the rest: the rest is given back
lzipWith : ((1 _ : a) -> (1 _ : b) -> c) -> (1 xs : LList a) -> (1 ys : LList b) ->
          LPair (LList c) (LPair (LList a) (LList b))
lzipWith f (x :: xs) (y :: ys) = case lzipWith f xs ys of
                                     (zs # rest) => (f x y :: zs) # rest
lzipWith f [] ys = [] # ([] # ys)
lzipWith f xs [] = [] # (xs # [])

failing "Inconsistent usage of x in case branches"
  lzipDrop : ((1 _ : a) -> (1 _ : b) -> c) -> (1 xs : LList a) -> (1 ys : LList b) ->
            LMaybe (LList c)
  lzipDrop f [] [] = Some []
  lzipDrop f (x :: xs) (y :: ys) = case lzipDrop f xs ys of
                                       None => None
                                       Some zs => Some (f x y :: zs)
  lzipDrop f [] (y :: ys) = None
  lzipDrop f (x :: xs) [] = None

-- an action that consumes each element; `io_bind` takes its continuation
-- linearly, `>>=` does not
ltraverse_ : ((1 _ : a) -> IO ()) -> (1 xs : LList a) -> IO ()
ltraverse_ f [] = pure ()
ltraverse_ f (x :: xs) = io_bind (f x) (\_ => ltraverse_ f xs)

failing "Trying to use linear name x in non-linear context"
  ltraverseBind : ((1 _ : a) -> IO ()) -> (1 xs : LList a) -> IO ()
  ltraverseBind f [] = pure ()
  ltraverseBind f (x :: xs) = f x >>= \_ => ltraverseBind f xs

-- Second copies, for unrestricted functions
lmapW : (a -> b) -> LList a -> LList b
lmapW f [] = []
lmapW f (x :: xs) = f x :: lmapW f xs

lfoldrW : (a -> b -> b) -> b -> LList a -> b
lfoldrW f z [] = z
lfoldrW f z (x :: xs) = f x (lfoldrW f z xs)

------------------------------------------------------------------------------
-- Functions that look at an element and drop it, or drop some: only
-- unrestricted.  A linear version needs another signature (give the element
-- back, or `Consumable` from `libs/linear`).

lfilter : (a -> Bool) -> LList a -> LList a
lfilter p [] = []
lfilter p (x :: xs) = if p x then x :: lfilter p xs else lfilter p xs

llookup : Eq a => a -> LList (LPair a b) -> Maybe b
llookup k [] = Nothing
llookup k ((k' # v) :: kvs) = if k == k' then Just v else llookup k kvs

lelem : Eq a => a -> LList a -> Bool
lelem x [] = False
lelem x (y :: ys) = x == y || lelem x ys

lsum : Num a => LList a -> a
lsum [] = 0
lsum (x :: xs) = x + lsum xs

llast : LList a -> Maybe a
llast [] = Nothing
llast [x] = Just x
llast (_ :: xs) = llast xs

lzip : LList a -> LList b -> LList (LPair a b)
lzip (x :: xs) (y :: ys) = (x # y) :: lzip xs ys
lzip _ _ = []

failing "Trying to use linear name x in non-linear context"
  lfilterLin : (a -> Bool) -> (1 xs : LList a) -> LList a
  lfilterLin p [] = []
  lfilterLin p (x :: xs) = if p x then x :: lfilterLin p xs else lfilterLin p xs

failing "There are 0 uses of linear name x"
  llastLin : (1 _ : LList a) -> LMaybe a
  llastLin [] = None
  llastLin [x] = Some x
  llastLin (x :: xs) = llastLin xs

------------------------------------------------------------------------------
-- A linear resource, to make the linear client honest

export
data Token : Type where
  MkToken : Nat -> Token

-- An unrestricted value inside a linear one: matching a linear `Ur`
-- binds its field unrestricted (1 * omega = omega)
data Ur : Type -> Type where
  MkUr : a -> Ur a

value : (1 _ : Token) -> Ur Nat
value (MkToken n) = MkUr n

bump : (1 _ : Token) -> Token
bump (MkToken n) = MkToken (S n)

merge : (1 _ : Token) -> (1 _ : Token) -> Token
merge (MkToken m) (MkToken n) = MkToken (m + n)

-- `MkToken` is not linear in its argument, so it can't go to `lmap`
tokens : Nat -> LList Token
tokens n = lmapW MkToken (lreplicate n 1)

failing "Mismatch between: Nat -> Token and (1 _ : ?a) -> ?b"
  tokensLin : Nat -> LList Token
  tokensLin n = lmap MkToken (lreplicate n 1)

------------------------------------------------------------------------------
-- The linear client

linearClient : (1 ts : LList Token) -> Nat
linearClient ts
    = let 1 ts1 = lappend (lreverse ts) [MkToken 10]
          1 ts2 = lmap bump ts1 in
      case lsplitAt 1 ts2 of
        (front # back) =>
          let 1 ts3 = lconcat [front, intersperse' back] in
          case llength ts3 of
            (n # ts4) =>
              case luncons ts4 of
                   None => n
                   Some (t # rest) =>
                     case value (merge t (lfoldr merge (MkToken 0) rest)) of
                          MkUr m => n + m
  where
    -- a linear separator can't be used: `lintersperse` copies it
    intersperse' : (1 _ : LList Token) -> LList Token
    intersperse' xs = xs

failing "Trying to use linear name t in non-linear context"
  copySep : (1 t : Token) -> (1 ts : LList Token) -> LList Token
  copySep t ts = lintersperse t ts

linearFolds : (1 ts : LList Token) -> Token
linearFolds ts = lfoldl merge (MkToken 0) ts

linearZip : (1 xs : LList Token) -> (1 ys : LList Token) -> Token
linearZip xs ys = case lzipWith merge xs ys of
                       (zs # (as # bs)) => merge (linearFolds zs) (merge (linearFolds as) (linearFolds bs))

linearIO : (1 ts : LList Token) -> IO ()
linearIO ts = ltraverse_ (\t => case value t of MkUr n => printLn n) ts

failing "Trying to use linear name t in non-linear context"
  linearIO' : (1 ts : LList Token) -> IO ()
  linearIO' ts = ltraverse_ (\t => printLn (value t)) ts

-- an unrestricted function can't be passed for a linear one
double : Nat -> Nat
double x = x + x

failing "Mismatch between: Nat -> Nat and (1 _ : ?a) -> ?b"
  mapDouble : LList Nat -> LList Nat
  mapDouble xs = lmap double xs

failing "Trying to use linear name x in non-linear context"
  mapPlus : LList Nat -> LList Nat
  mapPlus xs = lmap (\x => x + x) xs

------------------------------------------------------------------------------
-- The unrestricted client: the same functions, with the list used many times

unrestrictedClient : LList Nat -> List Nat
unrestrictedClient xs
    = let ys = lappend xs (lreverse xs) in
      let (n # _) = llength ys in
      let (front # back) = lsplitAt 2 ys in
      let zs = lconcat [front, lintersperse 0 back, lreplicate 2 7] in
      [n, lsum zs, lsum (lmapW (* 2) xs), lfoldrW (+) 0 ys,
       lsum (lfilter (> 1) ys), maybe 0 id (llookup 2 (lzip xs ys)),
       if lelem 3 ys then 1 else 0, maybe 0 id (llast zs)]
       ++ (case luncons xs of
                None => []
                Some (h # _) => [h, h])

-- The linear versions of the higher-order functions take a function that
-- is linear in its argument: functions that happen to be linear work
-- unrestricted too
linearFunction : (1 _ : Nat) -> Nat
linearFunction x = x

unrestrictedLinearFn : LList Nat -> Nat
unrestrictedLinearFn xs = lsum (lmap linearFunction xs) + lsum (lmapW S xs)

------------------------------------------------------------------------------
-- From `List` to `LList` and back, with the Prelude's higher-order functions
-- and partially applied constructors (eta-expanded where `List` expects an
-- unrestricted function)

fromList : List a -> LList a
fromList = foldr (::) []

ltoList : LList a -> List a
ltoList [] = []
ltoList (x :: xs) = x :: ltoList xs

singletons : List a -> List (LList a)
singletons xs = Prelude.map (\x => [x]) xs

conses : List a -> List (LList a -> LList a)
conses xs = Prelude.map {f = List} (::) xs

pairs : List a -> List b -> List (LPair a b)
pairs = zipWith (#)

unUr : Ur a -> a
unUr (MkUr x) = x

export
main : IO ()
main = do printLn (linearClient (tokens 3))
          printLn (unUr (value (linearFolds (tokens 4))))
          printLn (unUr (value (linearZip (tokens 2) (tokens 3))))
          linearIO (tokens 2)
          printLn (unrestrictedClient (fromList [1, 2, 3]))
          printLn (unrestrictedLinearFn (fromList [1, 2, 3]))
          printLn (Prelude.map ltoList (Prelude.map (\f => f [0]) (conses [1, 2])))
          printLn (Prelude.map ltoList (singletons [1, 2]))
          printLn (Prelude.map (\(x # y) => (x, y)) (pairs [1, 2] ['a', 'b']))
