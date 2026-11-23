||| Immutable arrays indexed by their size, with constant-time indexing.
|||
||| An `Array n a` holds `n` elements of type `a`, in the slots of a primitive
||| array (`Data.IOArray.Prims`), and is built once: by `tabulate`,
||| `replicate`, `fromVect`, `fromList`, `map`, `zipWith` or `replaceAt`, each
||| of which makes a new array.  `index` takes a `Fin n`, so it needs no check
||| and cannot fail, and costs a few instructions where `Data.Vect.index` walks
||| the vector.
|||
||| Nothing changes an array once it is made: `replaceAt` copies.  This is
||| what makes the pure interface sound, see `perform` below.
module Data.Array

import Data.Fin
import Data.IOArray.Prims
import Data.Vect
import public Data.Zippable

%default total

||| An immutable array of `n` elements.
|||
||| The `Int` is the number of elements, which is `n` (the index is erased at
||| run time, and the folds need it).  The functions of this module only make
||| arrays whose primitive array has that many slots, all written.
export
data Array : (n : Nat) -> Type -> Type where
  MkArray : (size : Int) -> ArrayData a -> Array n a

-- Why the pure interface is sound
--
-- The primitive array operations are `PrimIO` actions.  `perform` runs one
-- and gives its result, as `unsafePerformIO` does (inlined: a call of
-- `unsafePerformIO` costs a closure for the action).  This is safe here
-- because the only actions run are
--   - making a new primitive array and writing its slots, before the array
--     is given to anyone: the writes cannot be seen from outside, and running
--     the whole action twice (if the compiler duplicated it) or once for two
--     equal expressions (if it shared them) makes arrays that are equal;
--   - reading a slot of an array that nobody writes any more: the same read
--     gives the same element whenever it is done.
-- No function of this module writes to an array that it did not make in the
-- same action.

%inline
perform : PrimIO a -> a
perform act = case act %MkWorld of
                   MkIORes res _ => res

%inline
intOf : Nat -> Int
intOf n = cast (natToInteger n)

-- The slot of a Fin: a Fin is a Nat at run time, and finToInteger is an
-- identity there (Compiler.Opts.Identity).
%inline
slot : Fin n -> Int
slot i = cast (finToInteger i)

-- A filler for the primitive array of an empty array, whose slots are never
-- read (there are none).  The primitives need a value to initialise the
-- slots with; for a non-empty array it is its first element.
%inline
noElement : a
noElement = believe_me ()

||| The array of no elements.
export
empty : Array 0 a
empty = MkArray 0 (perform (prim__newArray 0 noElement))

-- Write `f k`, ..., `f (k + r - 1)` to the slots k, ..., k + r - 1.  The
-- Fins are made with natToFinLT, an identity at run time, as in
-- Data.Vect.Fin.tabulateFrom.
fillFrom : ArrayData a -> (Fin n -> a) -> (k, r : Nat) -> (0 _ : k + r = n) -> PrimIO ()
fillFrom arr f k Z prf w = MkIORes () w
fillFrom arr f k (S r) prf w
    = let i = natToFinLT k {prf = ltOfPlusSucc k r prf} in
          case prim__arraySet arr (intOf k) (f i) w of
               MkIORes _ w' => fillFrom arr f (S k) r (trans (plusSuccRightSucc k r) prf) w'

||| The array of `f i` for every `i : Fin n`, in order.  Each `f i` is
||| computed once.
export
tabulate : {n : Nat} -> (Fin n -> a) -> Array n a
tabulate {n = Z} f = empty
tabulate {n = S m} f
    = MkArray (intOf (S m)) $ perform $ \w =>
        case prim__newArray (intOf (S m)) (f FZ) w of
             MkIORes arr w' => case fillFrom arr f 1 m Refl w' of
                                    MkIORes _ w'' => MkIORes arr w''

||| The array of `n` copies of `x`.
export
replicate : (n : Nat) -> a -> Array n a
replicate n x = MkArray (intOf n) (perform (prim__newArray (intOf n) x))

-- Write the elements of a list to the slots from `k` on.
fillList : ArrayData a -> Int -> List a -> PrimIO ()
fillList arr k [] w = MkIORes () w
fillList arr k (x :: xs) w
    = case prim__arraySet arr k x w of
           MkIORes _ w' => fillList arr (k + 1) xs w'

-- An array of the elements of a list that has `size` elements, at least one.
fromCells : (size : Int) -> a -> List a -> Array n a
fromCells size x xs
    = MkArray size $ perform $ \w =>
        case prim__newArray size x w of
             MkIORes arr w' => case fillList arr 1 xs w' of
                                    MkIORes _ w'' => MkIORes arr w''

||| The array of the elements of a vector, in order.
export
fromVect : Vect n a -> Array n a
fromVect [] = MkArray 0 (perform (prim__newArray 0 noElement))
fromVect xs@(x :: rest) = fromCells (intOf (length xs)) x (toList rest)

||| The array of the elements of a list, in order, with its length.
export
fromList : List a -> (n : Nat ** Array n a)
fromList [] = (0 ** empty)
fromList xs@(x :: rest)
    = let n = length xs in (n ** fromCells (intOf n) x rest)

||| The element at a position, in constant time.
export %inline
index : Fin n -> Array n a -> a
index i (MkArray _ arr) = perform (prim__arrayGet arr (slot i))

||| The number of elements, `n`, in constant time.
export %inline
size : Array n a -> Nat
size (MkArray s _) = integerToNat (cast s)

-- (In the loops below, the element is read first, in a `let` of its own:
-- that lets the function be applied to all its arguments at once, which on
-- RefC is one call instead of two.)

-- foldr from the slot `k` down, onto `acc`.
foldrFrom : ArrayData e -> (e -> acc -> acc) -> acc -> Int -> acc
foldrFrom arr f acc k
    = if k < 0 then acc
         else let x = perform (prim__arrayGet arr k) in
                  assert_total $ foldrFrom arr f (f x acc) (k - 1)

-- foldl from the slot `k` up to `size - 1`.
foldlFrom : ArrayData e -> Int -> (acc -> e -> acc) -> acc -> Int -> acc
foldlFrom arr size f acc k
    = if k >= size then acc
         else let x = perform (prim__arrayGet arr k) in
                  assert_total $ foldlFrom arr size f (f acc x) (k + 1)

||| The elements as a vector, in order (with `tabulate` of `Data.Vect`, O(n)).
export
toVect : {n : Nat} -> Array n a -> Vect n a
toVect arr = Fin.tabulate (\i => index i arr)

-- A new primitive array of `size` slots, at least one, with `x` in the
-- first one and `fill arr` writing the others.
build : Int -> b -> (ArrayData b -> PrimIO ()) -> Array n b
build size x fill
    = MkArray size $ perform $ \w =>
        case prim__newArray size x w of
             MkIORes arr w' => case fill arr w' of
                                    MkIORes _ w'' => MkIORes arr w''

%inline
emptyOf : Array n b
emptyOf = MkArray 0 (perform (prim__newArray 0 noElement))

-- Write `f k` to the slots from `k` to `size - 1`.
generateFrom : Int -> (Int -> b) -> ArrayData b -> Int -> PrimIO ()
generateFrom size f arr k w
    = if k >= size then MkIORes () w
         else case prim__arraySet arr k (f k) w of
                   MkIORes _ w' => assert_total $ generateFrom size f arr (k + 1) w'

-- The array of `size` slots, slot `k` being `f k`.
generate : Int -> (Int -> b) -> Array n b
generate size f
    = if size <= 0 then emptyOf
                   else build size (f 0) (\arr => generateFrom size f arr 1)

-- Write `f` of the slots from `k` on of the first array to the second.
mapFrom : Int -> (a -> b) -> ArrayData a -> ArrayData b -> Int -> PrimIO ()
mapFrom size f src dst k w
    = if k >= size then MkIORes () w
         else let x = perform (prim__arrayGet src k) in
                  case prim__arraySet dst k (f x) w of
                       MkIORes _ w' => assert_total $ mapFrom size f src dst (k + 1) w'

-- Write `f` of the slots from `k` on of two arrays to a third.
zipFrom : Int -> (a -> b -> c) -> ArrayData a -> ArrayData b -> ArrayData c -> Int -> PrimIO ()
zipFrom size f xs ys dst k w
    = if k >= size then MkIORes () w
         else let x = perform (prim__arrayGet xs k)
                  y = perform (prim__arrayGet ys k) in
                  case prim__arraySet dst k (f x y) w of
                       MkIORes _ w' => assert_total $ zipFrom size f xs ys dst (k + 1) w'

%inline
get : ArrayData a -> Int -> a
get arr k = perform (prim__arrayGet arr k)

-- A copy of an array of `s` slots, at least one, with `x` in the slot `j`.
-- (The copy is done by the backend, in a few instructions per slot.)
copyWith : Int -> ArrayData a -> Int -> a -> Array n a
copyWith s arr j x
    = build s x $ \dst, w =>
        case prim__arrayCopy arr 0 dst 0 s w of
             MkIORes _ w' => prim__arraySet dst j x w'

||| A copy of the array with the element at a position replaced: O(n).
export
replaceAt : Fin n -> a -> Array n a -> Array n a
replaceAt i x (MkArray s arr) = copyWith s arr (slot i) x

||| A copy of the array with the element at a position updated: O(n).
export
updateAt : Fin n -> (a -> a) -> Array n a -> Array n a
updateAt i f (MkArray s arr) = let j = slot i in copyWith s arr j (f (get arr j))

export
Functor (Array n) where
  map f (MkArray s arr)
      = if s <= 0 then emptyOf
                  else build s (f (get arr 0)) (\dst => mapFrom s f arr dst 1)

export
Foldable (Array n) where
  foldr f e (MkArray s arr) = foldrFrom arr f e (s - 1)
  foldl f e (MkArray s arr) = foldlFrom arr s f e 0
  null (MkArray s _) = s <= 0
  toList (MkArray s arr) = foldrFrom arr (::) [] (s - 1)

export
Zippable (Array n) where
  zipWith f (MkArray s xs) (MkArray _ ys)
      = if s <= 0 then emptyOf
                  else build s (f (get xs 0) (get ys 0)) (\dst => zipFrom s f xs ys dst 1)
  zipWith3 f (MkArray s xs) (MkArray _ ys) (MkArray _ zs)
      = generate s (\k => f (get xs k) (get ys k) (get zs k))
  unzipWith f arr = let bcs = map f arr in (map fst bcs, map snd bcs)
  unzipWith3 f arr
      = let bcds = map f arr in (map fst bcds, map (fst . snd) bcds, map (snd . snd) bcds)

export
Eq a => Eq (Array n a) where
  MkArray s xs == MkArray _ ys = go 0
    where
      go : Int -> Bool
      go k = k >= s || (get xs k == get ys k && assert_total (go (k + 1)))

||| Shown as the list of its elements, as a `Vect` is.
export
Show a => Show (Array n a) where
  showPrec d arr = showPrec d (toList arr)
