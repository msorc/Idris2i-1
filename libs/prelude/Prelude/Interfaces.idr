module Prelude.Interfaces

import Builtin
import Prelude.Basics
import Prelude.EqOrd
import Prelude.Num

%default total

-------------
-- ALGEBRA --
-------------

||| Sets equipped with a single binary operation that is associative.  Must
||| satisfy the following laws:
|||
||| + Associativity of `<+>`:
|||     forall a b c, a <+> (b <+> c) == (a <+> b) <+> c
public export
interface Semigroup ty where
  constructor MkSemigroup
  (<+>) : ty -> ty -> ty

||| `foldl (\acc, x => acc <+> f x) z xs`, as a loop: the pieces are combined
||| from the left.  For a `<+>` whose cost does not grow with its left
||| argument (adding numbers, inserting into a map, `SnocList`), the best way
||| to implement `foldMapListImpl`; see `foldMapListBalanced` for the
||| others.
public export
foldMapListGo : Semigroup ty => (a -> ty) -> ty -> List a -> ty
foldMapListGo f acc [] = acc
foldMapListGo f acc (x :: xs) = foldMapListGo f (acc <+> f x) xs

||| The same as `foldMapListGo` for a `<+>` that is associative, with the
||| pieces combined in a balanced way instead of from the left.  The default
||| of `foldMapListImpl`.
|||
||| A left fold costs, for a `<+>` that copies its left argument (`List`,
||| `String`, a user type that wraps them), a copy of all that has been
||| collected at every step: time quadratic in the number of elements.  Here
||| the pieces are combined from the left in chunks of 16, and the results
||| for the chunks are kept as a stack of partial results, as the digits of a
||| binary counter: a new one is put on top, and as long as the number of
||| chunks so far is even the top two are combined (the older on the left).
||| The stack holds one partial result for every 1 in the binary form of the
||| number of chunks, each a combination of 2^k neighbouring ones, and the
||| ones at the end are combined from the smallest.  However `<+>` costs in
||| its two arguments, each piece is combined `O(log n)` times with one of its
||| size, or sits in a chunk of at most 16: `O(n log n)` for `n` pieces of
||| constant size where `<+>` costs the sum of the sizes of its arguments, and
||| `O(n)` where it does not depend on them, whether `<+>` copies its left or
||| its right argument.  The order of the operands is kept, so a `<+>` that is
||| not commutative is fine; one that is not associative is not (the nesting
||| differs from that of a left fold from the 17th piece on).
|||
||| The accumulator `z` is on the left of the first piece, as in a left fold,
||| so that the result is the same as that of `foldMapListGo` for up to 16
||| pieces, `z` for no pieces and `z <+> f x` for one.
public export
foldMapListBalanced : Semigroup ty => (a -> ty) -> ty -> List a -> ty
foldMapListBalanced f acc [] = acc
foldMapListBalanced f acc (x :: xs) = loop 15 1 (acc <+> f x) xs []
  where
    -- Put the result `v` for the chunk number `k` on the stack `us` of the
    -- results for the chunks before it: combine as long as `k` is even.
    push : Int -> ty -> List ty -> List ty
    push k v [] = [v]
    push k v (u :: us) =
      if prim__and_Int k 1 == 0 then push (prim__shr_Int k 1) (u <+> v) us else v :: u :: us

    -- Combine from the smallest, the newest, to the largest: their sizes add
    -- up to little more than the largest one.
    finish : ty -> List ty -> ty
    finish r [] = r
    finish r (u :: us) = finish (u <+> r) us

    -- `c` more pieces fit into the chunk `k` that is `cur` so far.
    loop : Int -> Int -> ty -> List a -> List ty -> ty
    loop c k cur [] us = finish cur us
    loop c k cur (y :: ys) us =
      if c == 0
         then loop 15 (k + 1) (f y) ys (push k cur us)
         else loop (c - 1) k (cur <+> f y) ys us

||| Sets equipped with a single binary operation that is associative, along with
||| a neutral element for that binary operation.  Must satisfy the following
||| laws:
|||
||| + Associativity of `<+>`:
|||     forall a b c, a <+> (b <+> c) == (a <+> b) <+> c
||| + Neutral for `<+>`:
|||     forall a, a <+> neutral == a
|||     forall a, neutral <+> a == a
public export
interface Semigroup ty => Monoid ty where
  constructor MkMonoid
  neutral : ty

  ||| `foldMap` of a list: combine the images of its elements with `<+>`.
  ||| `foldMap` for `List` is this, so `concat`, `concatMap` and `foldMap`
  ||| over a list take the cost of the monoid's way of combining many values.
  ||| It is a method because the best way depends on the monoid.  The
  ||| default, `foldMapListBalanced`, combines neighbours in a balanced way,
  ||| which is fast for a `<+>` that copies one of its arguments, on either
  ||| side, as that of a wrapper of a `List`, a `String` or a `SnocList`: a
  ||| left fold copies all that has been collected at every step.  A monoid
  ||| whose `<+>` is cheap in its left argument (numbers, maps, `SnocList`)
  ||| does less work with `foldMapListGo f neutral`, the left fold; `List`
  ||| and `String` build the result at once.  The result must be that of a
  ||| left fold, `foldl (\acc, x => acc <+> f x) neutral`, if `<+>` is
  ||| associative.
  ||| @ f The function to apply to each element.
  foldMapListImpl : (f : fmElem -> ty) -> List fmElem -> ty
  foldMapListImpl f xs = foldMapListBalanced f neutral xs

public export
Semigroup () where
  _ <+> _ = ()

public export
Monoid () where
  neutral = ()

public export
Semigroup a => Semigroup b => Semigroup (a, b) where
  (x, y) <+> (v, w) = (x <+> v, y <+> w)

public export
Monoid a => Monoid b => Monoid (a, b) where
  neutral = (neutral, neutral)

public export
Semigroup Ordering where
  LT <+> _ = LT
  GT <+> _ = GT
  EQ <+> o =  o

public export
Monoid Ordering where
  neutral = EQ
  foldMapListImpl f xs = foldMapListGo f neutral xs

public export
Semigroup b => Semigroup (a -> b) where
  (f <+> g) x = f x <+> g x

public export
Monoid b => Monoid (a -> b) where
  neutral _ = neutral

---------------------------------------------------------
-- FUNCTOR, BIFUNCTOR, APPLICATIVE, ALTERNATIVE, MONAD --
---------------------------------------------------------

||| Functors allow a uniform action over a parameterised type.
||| @ f a parameterised type
public export
interface Functor (0 f : Type -> Type) where
  constructor MkFunctor
  ||| Apply a function across everything of type 'a' in a parameterised type
  ||| @ f the parameterised type
  ||| @ func the function to apply
  map : (func : a -> b) -> f a -> f b

||| An infix alias for `map`, applying a function across everything of type 'a'
||| in a parameterised type.
||| @ f the parameterised type
||| @ func the function to apply
%inline %tcinline public export
(<$>) : Functor f => (func : a -> b) -> f a -> f b
(<$>) func x = map func x

||| Flipped version of `<$>`, an infix alias for `map`, applying a function across
||| everything of type 'a' in a parameterised type.
||| @ f the parameterised type
||| @ func the function to apply
%inline %tcinline public export
(<&>) : Functor f => f a -> (func : a -> b) -> f b
(<&>) x func = map func x

||| Run something for effects, replacing the return value with a given parameter.
%inline %tcinline public export
(<$) : Functor f => b -> f a -> f b
(<$) b = map (const b)

||| Flipped version of `<$`.
%inline %tcinline public export
($>) : Functor f => f a -> b -> f b
($>) fa b = map (const b) fa

||| Run something for effects, throwing away the return value.
%inline %tcinline public export
ignore : Functor f => f a -> f ()
ignore = map (const ())

namespace Functor
  ||| Composition of functors is a functor.
  public export
  [Compose] (l : Functor f) => (r : Functor g) => Functor (f . g) where
    map = map . map

||| Bifunctors
||| @f The action of the Bifunctor on pairs of objects
||| A minimal definition includes either `bimap` or both `mapFst` and `mapSnd`.
public export
interface Bifunctor (0 f : Type -> Type -> Type) where
  constructor MkBifunctor
  ||| The action of the Bifunctor on pairs of morphisms
  |||
  ||| ````idris example
  ||| bimap (\x => x + 1) reverse (1, "hello") == (2, "olleh")
  ||| ````
  |||
  total
  bimap : (a -> c) -> (b -> d) -> f a b -> f c d
  bimap f g = mapFst f . mapSnd g

  ||| The action of the Bifunctor on morphisms pertaining to the first object
  |||
  ||| ````idris example
  ||| mapFst (\x => x + 1) (1, "hello") == (2, "hello")
  ||| ````
  |||
  total
  mapFst : (a -> c) -> f a b -> f c b
  mapFst f = bimap f id

  ||| The action of the Bifunctor on morphisms pertaining to the second object
  |||
  ||| ````idris example
  ||| mapSnd reverse (1, "hello") == (1, "olleh")
  ||| ````
  |||
  total
  mapSnd : (b -> d) -> f a b -> f a d
  mapSnd = bimap id

public export %tcinline
mapHom : Bifunctor f => (a -> b) -> f a a -> f b b
mapHom f = bimap f f

namespace Bifunctor

  ||| Composition of a bifunctor and a functor is a bifunctor.
  public export %inline
  [Compose] (l : Functor f) => (r : Bifunctor g) => Bifunctor (f .: g) where
    bimap = map .: bimap
    mapFst = map . mapFst
    mapSnd = map . mapSnd

public export
interface Functor f => Applicative (0 f : Type -> Type) where
  constructor MkApplicative
  pure : a -> f a
  (<*>) : f (a -> b) -> f a -> f b

public export %tcinline
(<*) : Applicative f => f a -> f b -> f a
a <* b = map const a <*> b

public export %tcinline
(*>) : Applicative f => f a -> f b -> f b
a *> b = map (const id) a <*> b

%allow_overloads pure
%allow_overloads (<*)
%allow_overloads (*>)

namespace Applicative
  ||| Composition of applicative functors is an applicative functor.
  public export
  [Compose] (l : Applicative f) => (r : Applicative g) => Applicative (f . g)
    using Functor.Compose where
      pure = pure . pure
      fun <*> x = [| fun <*> x |]

||| An alternative functor has a notion of disjunction.
||| @f is the underlying applicative functor
||| We expect (f a, empty, (<|>)) to be a type family of monoids.
public export
interface Applicative f => Alternative (0 f : Type -> Type) where
  constructor MkAlternative
  empty : f a
  (<|>) : f a -> Lazy (f a) -> f a

||| Monad
||| @m The underlying functor
||| A minimal definition includes either `(>>=)` or `join`.
public export
interface Applicative m => Monad (0 m : Type -> Type) where
  constructor MkMonad
  ||| Also called `bind`.
  total
  (>>=) : m a -> (a -> m b) -> m b

  ||| Also called `flatten` or mu.
  total
  join : m (m a) -> m a

  -- default implementations
  (>>=) x f = join (f <$> x)
  join x = x >>= id

%allow_overloads (>>=)

||| Right-to-left monadic bind, flipped version of `>>=`.
%inline %tcinline public export
(=<<) : Monad m => (a -> m b) -> m a -> m b
(=<<) = flip (>>=)

||| Sequencing of effectful composition
%inline %tcinline public export
(>>) : Monad m => m () -> Lazy (m b) -> m b
a >> b = a >>= \_ => b

||| Left-to-right Kleisli composition of monads.
public export %tcinline
(>=>) : Monad m => (a -> m b) -> (b -> m c) -> (a -> m c)
(>=>) f g = \x => f x >>= g

||| Right-to-left Kleisli composition of monads, flipped version of `>=>`.
public export %tcinline
(<=<) : Monad m => (b -> m c) -> (a -> m b) -> (a -> m c)
(<=<) = flip (>=>)

||| `guard a` is `pure ()` if `a` is `True` and `empty` if `a` is `False`.
public export
guard : Alternative f => Bool -> f ()
guard x = if x then pure () else empty

||| Conditionally execute an applicative expression when the boolean is true.
public export
when : Applicative f => Bool -> Lazy (f ()) -> f ()
when True f = f
when False f = pure ()

||| Execute an applicative expression unless the boolean is true.
%inline %tcinline public export
unless : Applicative f => Bool -> Lazy (f ()) -> f ()
unless = when . not

---------------------------
-- FOLDABLE, TRAVERSABLE --
---------------------------

||| The `Foldable` interface describes how you can iterate over the elements in
||| a parameterised type and combine the elements together, using a provided
||| function, into a single result.
||| @ t The type of the 'Foldable' parameterised type.
||| A minimal definition includes `foldr`
public export
interface Foldable (0 t : Type -> Type) where
  constructor MkFoldable
  ||| Successively combine the elements in a parameterised type using the
  ||| provided function, starting with the element that is in the final position
  ||| i.e. the right-most position.
  ||| @ func  The function used to 'fold' an element into the accumulated result
  ||| @ init  The starting value the results are being combined into
  ||| @ input The parameterised type
  foldr : (func : elem -> acc -> acc) -> (init : acc) -> (input : t elem) -> acc

  ||| The same as `foldr` but begins the folding from the element at the initial
  ||| position in the data structure i.e. the left-most position.
  ||| @ func  The function used to 'fold' an element into the accumulated result
  ||| @ init  The starting value the results are being combined into
  ||| @ input The parameterised type
  foldl : (func : acc -> elem -> acc) -> (init : acc) -> (input : t elem) -> acc
  foldl f z t = foldr (flip (.) . flip f) id t z

  ||| Test whether the structure is empty.
  ||| @ acc The accumulator value which is specified to be lazy
  null : t elem -> Bool
  null xs = foldr {acc = Lazy Bool} (\ _,_ => False) True xs

  ||| Similar to `foldl`, but uses a function wrapping its result in a `Monad`.
  ||| Consequently, the final value is wrapped in the same `Monad`.
  foldlM : Monad m => (funcM : acc -> elem -> m acc) -> (init : acc) -> (input : t elem) -> m acc
  foldlM fm a0 = foldl (\ma, b => ma >>= flip fm b) (pure a0)

  ||| Produce a list of the elements contained in the parametrised type.
  toList : t elem -> List elem
  toList = foldr (::) []

  ||| Maps each element to a value and combine them.
  ||| For performance reasons, this should wherever
  ||| be implemented with tail recursion.
  ||| @ f The function to apply to each element.
  foldMap : Monoid m => (f : a -> m) -> t a -> m
  foldMap f = foldr ((<+>) . f) neutral

||| Combine each element of a structure into a monoid.
%inline %tcinline public export
concat : Monoid a => Foldable t => t a -> a
concat = foldMap id

||| Combine into a monoid the collective results of applying a function to each
||| element of a structure.
%inline %tcinline public export
concatMap : Monoid m => Foldable t => (a -> m) -> t a -> m
concatMap = foldMap

namespace Bool.Lazy
  namespace Semigroup
    public export
    [Any] Semigroup (Lazy Bool) where
      x <+> y = force x || y

    public export
    [All] Semigroup (Lazy Bool) where
      x <+> y = force x && y

  namespace Monoid
    public export
    [Any] Monoid (Lazy Bool) using Semigroup.Any where
      neutral = delay False
      foldMapListImpl f xs = foldMapListGo @{Semigroup.Any} f (delay False) xs

    public export
    [All] Monoid (Lazy Bool) using Semigroup.All where
      neutral = delay True
      foldMapListImpl f xs = foldMapListGo @{Semigroup.All} f (delay True) xs

||| The conjunction of all elements of a structure containing lazy boolean
||| values.  `and` short-circuits from left to right, evaluating until either an
||| element is `False` or no elements remain.
public export %tcinline
and : Foldable t => t (Lazy Bool) -> Bool
and = force . concat @{All}

||| The disjunction of all elements of a structure containing lazy boolean
||| values.  `or` short-circuits from left to right, evaluating either until an
||| element is `True` or no elements remain.
public export %tcinline
or : Foldable t => t (Lazy Bool) -> Bool
or = force . concat @{Any}

namespace Bool
  namespace Semigroup
    public export
    [Any] Semigroup Bool where
      x <+> y = x || delay y

    public export
    [All] Semigroup Bool where
      x <+> y = x && delay y

  namespace Monoid
    public export
    [Any] Monoid Bool using Bool.Semigroup.Any where
      neutral = False
      foldMapListImpl f xs = foldMapListGo @{Bool.Semigroup.Any} f False xs

    public export
    [All] Monoid Bool using Bool.Semigroup.All where
      neutral = True
      foldMapListImpl f xs = foldMapListGo @{Bool.Semigroup.All} f True xs

||| The disjunction of the collective results of applying a predicate to all
||| elements of a structure.  `any` short-circuits from left to right.
%inline %tcinline public export
any : Foldable t => (a -> Bool) -> t a -> Bool
any = foldMap @{%search} @{Any}

||| The conjunction of the collective results of applying a predicate to all
||| elements of a structure.  `all` short-circuits from left to right.
%inline %tcinline public export
all : Foldable t => (a -> Bool) -> t a -> Bool
all = foldMap @{%search} @{All}

namespace Num
  namespace Semigroup
    public export
    [Additive] Num a => Semigroup a where
      (<+>) = (+)

    public export
    [Multiplicative] Num a => Semigroup a where
      (<+>) = (*)

  namespace Monoid
    public export
    [Additive] Num a => Monoid a using Semigroup.Additive where
      neutral = 0
      foldMapListImpl f xs = foldMapListGo f neutral xs

    public export
    [Multiplicative] Num a => Monoid a using Semigroup.Multiplicative where
      neutral = 1
      foldMapListImpl f xs = foldMapListGo f neutral xs

||| Add together all the elements of a structure.
public export %tcinline
sum : Num a => Foldable t => t a -> a
sum = concat @{Additive}

||| Add together all the elements of a structure.
||| Same as `sum` but tail recursive.
export %tcinline
sum' : Num a => Foldable t => t a -> a
sum' = sum

||| Multiply together all elements of a structure.
public export %tcinline
product : Num a => Foldable t => t a -> a
product = concat @{Multiplicative}

||| Multiply together all elements of a structure.
||| Same as `product` but tail recursive.
export %tcinline
product' : Num a => Foldable t => t a -> a
product' = product

||| Map each element of a structure to a computation, evaluate those
||| computations and discard the results.
public export %tcinline
traverse_ : Applicative f => Foldable t => (a -> f b) -> t a -> f ()
traverse_ f = foldr ((*>) . f) (pure ())

||| Evaluate each computation in a structure and discard the results.
public export %tcinline
sequence_ : Applicative f => Foldable t => t (f a) -> f ()
sequence_ = foldr (*>) (pure ())

||| Like `traverse_` but with the arguments flipped.
public export %tcinline
for_ : Applicative f => Foldable t => t a -> (a -> f b) -> f ()
for_ = flip traverse_

public export
[SemigroupApplicative] Applicative f => Semigroup a => Semigroup (f a) where
  x <+> y = [| x <+> y |]

public export
[MonoidApplicative] Applicative f => Monoid a => Monoid (f a) using SemigroupApplicative where
  neutral = pure neutral

namespace Lazy
  public export
  [SemigroupAlternative] Alternative f => Semigroup (Lazy (f a)) where
    x <+> y = force x <|> y

  public export
  [MonoidAlternative] Alternative f => Monoid (Lazy (f a)) using Lazy.SemigroupAlternative where
    neutral = delay empty

public export
[SemigroupAlternative] Alternative f => Semigroup (f a) where
  x <+> y = x <|> delay y

public export
[MonoidAlternative] Alternative f => Monoid (f a) using Interfaces.SemigroupAlternative where
  neutral = empty

||| Fold using Alternative.
|||
||| If you have a left-biased alternative operator `<|>`, then `choice` performs
||| left-biased choice from a list of alternatives, which means that it
||| evaluates to the left-most non-`empty` alternative.
|||
||| If the list is empty, or all values in it are `empty`, then it evaluates to
||| `empty`.
|||
||| Example:
|||
||| ```
||| -- given a parser expression like:
||| expr = literal <|> keyword <|> funcall
|||
||| -- choice lets you write this as:
||| expr = choice [literal, keyword, funcall]
||| ```
|||
||| Note: In Haskell, `choice` is called `asum`.
%inline %tcinline public export
choice : Alternative f => Foldable t => t (Lazy (f a)) -> f a
choice = force . concat @{Lazy.MonoidAlternative}

||| A fused version of `choice` and `map`.
%inline %tcinline public export
choiceMap : Alternative f => Foldable t => (a -> f b) -> t a -> f b
choiceMap = foldMap @{%search} @{MonoidAlternative}

namespace Foldable
  ||| Composition of foldables is foldable.
  public export %tcinline
  [Compose] (l : Foldable t) => (r : Foldable f) => Foldable (t . f) where
    foldr = foldr . flip . foldr
    foldl = foldl . foldl
    null tf = null tf || all null tf
    foldMap = foldMap . foldMap

||| `Bifoldable` identifies foldable structures with two different varieties
||| of elements (as opposed to `Foldable`, which has one variety of element).
||| Common examples are `Either` and `Pair`.
||| A minimal definition includes `bifoldr`
public export
interface Bifoldable (0 p : Type -> Type -> Type) where
  constructor MkBifoldable
  bifoldr : (a -> acc -> acc) -> (b -> acc -> acc) -> acc -> p a b -> acc

  bifoldl : (acc -> a -> acc) -> (acc -> b -> acc) -> acc -> p a b -> acc
  bifoldl f g z t = bifoldr (flip (.) . flip f) (flip (.) . flip g) id t z

  binull : p a b -> Bool
  binull t = bifoldr {acc = Lazy Bool} (\ _,_ => False) (\ _,_ => False) True t

||| Analogous to `foldMap` but for `Bifoldable` structures
public export %tcinline
bifoldMap : Monoid acc => Bifoldable p => (a -> acc) -> (b -> acc) -> p a b -> acc
bifoldMap f g = bifoldr ((<+>) . f) ((<+>) . g) neutral

||| Like Bifunctor's `mapFst` but for `Bifoldable` structures
public export %tcinline
bifoldMapFst : Monoid acc => Bifoldable p => (a -> acc) -> p a b -> acc
bifoldMapFst f = bifoldMap f (const neutral)

namespace Bifoldable

  ||| Composition of a bifoldable and a foldable is bifoldable.
  public export %tcinline
  [Compose] (l : Foldable f) => (r : Bifoldable p) => Bifoldable (f .: p) where
    bifoldr = foldr .: flip .: bifoldr
    bifoldl = foldl .: bifoldl
    binull fp = null fp || all binull fp

public export
interface (Functor t, Foldable t) => Traversable (0 t : Type -> Type) where
  constructor MkTraversable
  ||| Map each element of a structure to a computation, evaluate those
  ||| computations and combine the results.
  traverse : Applicative f => (a -> f b) -> t a -> f (t b)

||| Evaluate each computation in a structure and collect the results.
public export %tcinline
sequence : Applicative f => Traversable t => t (f a) -> f (t a)
sequence = traverse id

||| Like `traverse` but with the arguments flipped.
%inline %tcinline public export
for : Applicative f => Traversable t => t a -> (a -> f b) -> f (t b)
for = flip traverse

public export
interface (Bifunctor p, Bifoldable p) => Bitraversable (0 p : Type -> Type -> Type) where
  constructor MkBitraversable
  ||| Map each element of a structure to a computation, evaluate those
  ||| computations and combine the results.
  bitraverse : Applicative f => (a -> f c) -> (b -> f d) -> p a b -> f (p c d)

||| Evaluate each computation in a structure and collect the results.
public export %tcinline
bisequence : Applicative f => Bitraversable p => p (f a) (f b) -> f (p a b)
bisequence = bitraverse id id

||| Like `bitraverse` but with the arguments flipped.
public export %tcinline
bifor :  Applicative f => Bitraversable p
      => p a b
      -> (a -> f c)
      -> (b -> f d)
      -> f (p c d)
bifor t f g = bitraverse f g t

namespace Traversable
  ||| Composition of traversables is traversable.
  public export %tcinline
  [Compose] (l : Traversable t) => (r : Traversable f) => Traversable (t . f)
    using Foldable.Compose Functor.Compose where
      traverse = traverse . traverse

namespace Bitraversable
  ||| Composition of a bitraversable and a traversable is bitraversable.
  public export %tcinline
  [Compose] (l : Traversable t) => (r : Bitraversable p) => Bitraversable (t .: p)
    using Bifoldable.Compose Bifunctor.Compose where
      bitraverse = traverse .: bitraverse

namespace Monad
  ||| Composition of a traversable monad and a monad is a monad.
  public export %tcinline
  [Compose] (l : Monad m) => (r : Monad t) => (tr : Traversable t) => Monad (m . t)
    using Applicative.Compose where
      a >>= f = a >>= map join . traverse f
