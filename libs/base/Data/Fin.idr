module Data.Fin

import Control.Function
import public Control.Ord
import Data.List1
import public Data.Maybe
import public Data.Nat
import public Data.So
import Decidable.Equality.Core

%default total

||| Numbers strictly less than some bound.  The name comes from "finite sets".
|||
||| It's probably not a good idea to use `Fin` for arithmetic, and they will be
||| exceedingly inefficient at run time.
||| @ n the upper bound
public export
data Fin : (n : Nat) -> Type where
    FZ : Fin (S k)
    FS : Fin k -> Fin (S k)

||| Coerce between Fins with equal indices
public export
coerce : {n : Nat} -> (0 eq : m = n) -> Fin m -> Fin n -- TODO: make linear
coerce {n = S _} eq FZ = FZ
coerce {n = Z} eq FZ impossible
coerce {n = S _} eq (FS k) = FS (coerce (injective eq) k)
coerce {n = Z} eq (FS k) impossible

%transform "coerce-identity" coerce eq k = replace {p = Fin} eq k

export
Uninhabited (Fin Z) where
  uninhabited FZ impossible
  uninhabited (FS f) impossible

export
Uninhabited (FZ = FS k) where
  uninhabited Refl impossible

export
Uninhabited (FS k = FZ) where
  uninhabited Refl impossible

export
Uninhabited (n = m) => Uninhabited (FS n = FS m) where
  uninhabited Refl @{nm} = uninhabited Refl @{nm}

export
Injective FS where
  injective Refl = Refl

||| Convert a Fin to a Nat
public export
finToNat : Fin n -> Nat
finToNat FZ = Z
finToNat (FS k) = S $ finToNat k

export
Eq (Fin n) where
  x == y = finToNat x == finToNat y

finToNatInjective : (fm : Fin k) -> (fn : Fin k) -> (finToNat fm) = (finToNat fn) -> fm = fn
finToNatInjective FZ     FZ     _    = Refl
finToNatInjective (FS _) FZ     Refl impossible
finToNatInjective FZ     (FS _) Refl impossible
finToNatInjective (FS m) (FS n) prf  =
  cong FS $ finToNatInjective m n $ injective prf

||| `finToNat` is injective
export
Injective Fin.finToNat where
 injective = (finToNatInjective _ _)

export
Cast (Fin n) Nat where
    cast = finToNat

||| Convert a Fin to an Integer
public export
finToInteger : Fin n -> Integer
finToInteger FZ     = 0
finToInteger (FS k) = 1 + finToInteger k

-- %builtin NaturalToInteger Data.Fin.finToInteger

export
Show (Fin n) where
  show = show . finToInteger

export
Cast (Fin n) Integer where
    cast = finToInteger

||| Weaken the bound on a Fin by 1
public export
weaken : Fin n -> Fin (S n)
weaken FZ     = FZ
weaken (FS k) = FS $ weaken k

||| Weaken the bound on a Fin by some amount
public export
weakenN : (0 n : Nat) -> Fin m -> Fin (m + n)
weakenN n FZ = FZ
weakenN n (FS f) = FS $ weakenN n f

||| Weaken the bound on a Fin using a constructive comparison
public export
weakenLTE : Fin n -> LTE n m -> Fin m
weakenLTE  FZ     LTEZero impossible
weakenLTE (FS _)  LTEZero impossible
weakenLTE  FZ    (LTESucc _) = FZ
weakenLTE (FS x) (LTESucc y) = FS $ weakenLTE x y

||| Attempt to tighten the bound on a Fin.
||| Return the tightened bound if there is one, else nothing.
export
strengthen : {n : _} -> Fin (S n) -> Maybe (Fin n)
strengthen {n = S _} FZ = Just FZ
strengthen {n = S _} (FS p) with (strengthen p)
  strengthen (FS _) | Nothing = Nothing
  strengthen (FS _) | Just q  = Just $ FS q
strengthen _ = Nothing

||| `strengthen` on `Integer`, used at run time in place of `strengthen` (a
||| `%transform` rule), and so in `finS` and the `Num` operations.
|||
||| This relies on the representation of `Fin` at run time: `Fin` has the
||| shape of `Nat` (calcNaty in the compiler), so on every backend a `Fin` is
||| the `Integer` it counts, and the same value is the `Fin n` when it is
||| below `n`: `believe_me x` is that value with its new type.
export
strengthenInteger : {n : _} -> Fin (S n) -> Maybe (Fin n)
strengthenInteger x
    = if finToInteger x < natToInteger n then Just (believe_me x) else Nothing

%transform "strengthenInteger" strengthen = strengthenInteger

||| Add some natural number to a Fin, extending the bound accordingly
||| @ n the previous bound
||| @ m the number to increase the Fin by
public export
shift : (m : Nat) -> Fin n -> Fin (m + n)
shift Z f = f
shift (S m) f = FS $ shift m f

||| Increment a Fin, wrapping on overflow
public export
finS : {n : Nat} -> Fin n -> Fin n
finS {n = S _} x = case strengthen x of
    Nothing => FZ
    Just y => FS y

||| The largest element of some Fin type
public export
last : {n : _} -> Fin (S n)
last {n=Z} = FZ
last {n=S _} = FS last

||| The finite complement of some Fin.
||| The number as far along as the input, but starting from the other end.
public export
complement : {n : Nat} -> Fin n -> Fin n
complement {n = S _} FZ = last
complement {n = S _} (FS x) = weaken $ complement x

namespace List

  ||| All of the Fin elements
  public export
  allFins : (n : Nat) -> List (Fin n)
  allFins Z = []
  allFins (S n) = FZ :: map FS (allFins n)

namespace List1

  ||| All of the Fin elements
  public export
  allFins : (n : Nat) -> List1 (Fin (S n))
  allFins Z = FZ ::: []
  allFins (S n) = FZ ::: map FS (forget (allFins n))


export
Ord (Fin n) where
  compare x y = compare (finToNat x) (finToNat y)

namespace Monoid

  public export
  [Minimum] {n : Nat} -> Monoid (Fin $ S n) using Semigroup.Minimum where
    neutral = last

  public export
  [Maximum] Monoid (Fin $ S n) using Semigroup.Maximum where
    neutral = FZ

public export
natToFinLT : (x : Nat) -> {0 n : Nat} ->
             {auto 0 prf : x `LT` n} ->
             Fin n
natToFinLT Z {prf = LTESucc _} = FZ
natToFinLT (S k) {prf = LTESucc _} = FS $ natToFinLT k

||| The counter of a loop over the Fins below `n` is below `n` while `r` of
||| them are left: used by the counter-based versions of `allFins`, `tabulate`
||| and `range`.
export
0 ltOfPlusSucc : (k, r : Nat) -> k + S r = n -> LT k n
ltOfPlusSucc k r prf
    = rewrite sym prf in
      rewrite sym (plusSuccRightSucc k r) in
              LTESucc (lteAddRight k)

||| The Fins from `k` on, `r` of them: `natToFinLT k`, ..., `natToFinLT (k + r - 1)`.
||| `natToFinLT` is an identity at run time and its proof is erased, so this
||| is O(r), where `allFins` maps `FS` over the list at each level, O(r^2).
||| Used at run time in place of `allFins` (`%transform` rules).
export
allFinsFrom : (k, r : Nat) -> (0 _ : k + r = n) -> List (Fin n)
allFinsFrom k Z prf = []
allFinsFrom k (S r) prf
    = natToFinLT k {prf = ltOfPlusSucc k r prf}
      :: allFinsFrom (S k) r (trans (plusSuccRightSucc k r) prf)

||| Counter-based `List.allFins`, used at run time in place of it (a
||| `%transform` rule).
export
allFinsCounter : (n : Nat) -> List (Fin n)
allFinsCounter n = allFinsFrom 0 n Refl

||| Counter-based `List1.allFins`, used at run time in place of it (a
||| `%transform` rule).
export
allFinsCounter1 : (n : Nat) -> List1 (Fin (S n))
allFinsCounter1 n = FZ ::: allFinsFrom 1 n Refl

-- (The rules name functions of this module only: the right-hand side of a
-- rule is used in the modules that call `allFins`, which may not see
-- Data.List1.)
%transform "allFinsCounter" List.allFins = allFinsCounter
%transform "allFinsCounter1" List1.allFins = allFinsCounter1

public export
natToFinLt : (x : Nat) -> {0 n : Nat} ->
             {auto 0 prf : So (x < n)} ->
             Fin n
natToFinLt x = let 0 p := ltOpReflectsLT x n prf in natToFinLT x

public export
natToFin : Nat -> (n : Nat) -> Maybe (Fin n)
natToFin x n = case isLT x n of
    Yes prf => Just $ natToFinLT x
    No contra => Nothing

||| Convert an `Integer` to a `Fin`, provided the integer is within bounds.
||| @n The upper bound of the Fin
public export
integerToFin : Integer -> (n : Nat) -> Maybe (Fin n)
integerToFin x Z = Nothing -- make sure 'n' is concrete, to save reduction!
integerToFin x n = if x >= 0 then natToFin (fromInteger x) n else Nothing

public export
maybeLTE : (x : Nat) -> (y : Nat) -> Maybe (x `LTE` y)
maybeLTE Z _ = Just LTEZero
maybeLTE (S x) (S y) = LTESucc <$> maybeLTE x y
maybeLTE _ _ = Nothing

public export
maybeLT : (x : Nat) -> (y : Nat) -> Maybe (x `LT` y)
maybeLT x y = maybeLTE (S x) y

public export
finFromInteger : (x : Integer) ->
                 {auto 0 prf : So (fromInteger x < n)} ->
                 Fin n
finFromInteger x = natToFinLt (fromInteger x)

-- Direct comparison between `Integer` and `Nat`.
-- We cannot convert the `Nat` to `Integer`, because that will not work with open terms;
-- but we cannot convert the `Integer` to `Nat` either, because that slows down typechecking
-- even when the function is unused (issue #2032)
public export
integerLessThanNat : Integer -> Nat -> Bool
integerLessThanNat 0 (S m) = True
integerLessThanNat x n with (x < the Integer 0)
  integerLessThanNat _ _     | True  = False                           -- don't support negative literals
  integerLessThanNat x (S m) | False = integerLessThanNat (x-1) m      -- recursive case
  integerLessThanNat x Z     | False = False                           -- `x >= 0` contradicts `x < Z`

||| Allow overloading of Integer literals for Fin.
||| @ x the Integer that the user typed
||| @ prf an automatically-constructed proof that `x` is in bounds
public export
fromInteger : (x : Integer) ->
              {auto 0 prf : So (integerLessThanNat x n)} ->
              Fin n
fromInteger x = finFromInteger x {prf = lemma prf} where
  -- to be minimally invasive, we just call the previous implementation.
  -- however, having a different proof obligation resolves #2032
  0 lemma : {x : Integer} -> So (integerLessThanNat x n) -> So (fromInteger {ty=Nat} x < n)
  lemma oh = believe_me oh

-- %builtin IntegerToNatural Data.Fin.fromInteger

||| Convert an Integer to a Fin in the required bounds/
||| This is essentially a composition of `mod` and `fromInteger`
public export
restrict : (n : Nat) -> Integer -> Fin (S n)
restrict n val = let -- `S n` is not zero, so neither is the divisor
                         val' = abs (assert_total $ mod val (cast (S n))) in
                     -- reasoning about primitives, so we need the
                     -- 'believe_me'. It's fine because val' must be
                     -- in the right range
                     fromInteger {n = S n} val'
                         {prf = believe_me {a=IsJust (Just val')} ItIsJust}

--------------------------------------------------------------------------------
-- Num
--------------------------------------------------------------------------------

-- `+` and `*` of `Num (Fin (S n))` are functions of their own (as `mapImpl`
-- is the `map` of `Functor List`), with the clauses the implementation had, so
-- that `%transform` rules can name them; at type-checking time `x + y`
-- unfolds to the same clauses.

||| The `+` of `Num (Fin (S n))`: addition modulo `S n`.
public export
finPlus : {n : Nat} -> Fin (S n) -> Fin (S n) -> Fin (S n)
finPlus FZ y = y
finPlus {n = S _} (FS x) y = finS $ finPlus (assert_smaller x (weaken x)) y

||| The `*` of `Num (Fin (S n))`: multiplication modulo `S n`.
public export
finMult : {n : Nat} -> Fin (S n) -> Fin (S n) -> Fin (S n)
finMult FZ y = FZ
finMult (FS x) y = finPlus y (finMult (assert_smaller x $ weaken x) y)

-- The run-time versions of `finPlus`, `finMult` and `complement` compute on
-- `Integer` and give the result with `believe_me`.  This relies on the
-- representation of `Fin` at run time: `Fin` has the shape of `Nat`
-- (calcNaty in the compiler), so on every backend a `Fin` is the `Integer` it
-- counts, and an `Integer` below `n` is a `Fin n`.

||| `finPlus` on `Integer`, used at run time in place of it (a `%transform`
||| rule).
export
finPlusInteger : {n : Nat} -> Fin (S n) -> Fin (S n) -> Fin (S n)
finPlusInteger x y
    = believe_me $ assert_total $
        (finToInteger x + finToInteger y) `mod` (natToInteger n + 1)

||| `finMult` on `Integer`, used at run time in place of it (a `%transform`
||| rule).
export
finMultInteger : {n : Nat} -> Fin (S n) -> Fin (S n) -> Fin (S n)
finMultInteger x y
    = believe_me $ assert_total $
        (finToInteger x * finToInteger y) `mod` (natToInteger n + 1)

||| `complement` on `Integer`, used at run time in place of it (a
||| `%transform` rule), and so in `negate` and `-`.
export
complementInteger : {n : Nat} -> Fin n -> Fin n
complementInteger x = believe_me (natToInteger n - 1 - finToInteger x)

%transform "finPlusInteger" finPlus = finPlusInteger
%transform "finMultInteger" finMult = finMultInteger
%transform "complementInteger" complement = complementInteger

public export
{n : Nat} -> Num (Fin (S n)) where
  (+) = finPlus
  (*) = finMult

  fromInteger = restrict n

public export
{n : Nat} -> Neg (Fin (S n)) where
  negate = finS . complement

  x - y = x + (negate y)

--------------------------------------------------------------------------------
-- DecEq
--------------------------------------------------------------------------------

public export
DecEq (Fin n) where
  decEq FZ FZ = Yes Refl
  decEq (FS f) (FS f') = decEqCong $ decEq f f'
  decEq FZ (FS f) = No absurd
  decEq (FS f) FZ = No absurd

namespace Equality

  ||| Pointwise equality of Fins
  ||| It is sometimes complicated to prove equalities on type-changing
  ||| operations on Fins.
  ||| This inductive definition can be used to simplify proof. We can
  ||| recover proofs of equalities by using `homoPointwiseIsEqual`.
  public export
  data Pointwise : Fin m -> Fin n -> Type where
    FZ : Pointwise FZ FZ
    FS : Pointwise k l -> Pointwise (FS k) (FS l)

  export infix 6 ~~~
  ||| Convenient infix notation for the notion of pointwise equality of Fins
  public export
  (~~~) : Fin m -> Fin n -> Type
  (~~~) = Pointwise

  export
  Uninhabited (FS k ~~~ FZ) where
    uninhabited FZ impossible
    uninhabited (FS _) impossible

  export
  Uninhabited (FZ ~~~ FS k) where
    uninhabited FZ impossible
    uninhabited (FS _) impossible

  ||| Pointwise equality is reflexive
  export
  reflexive : {k : Fin m} -> k ~~~ k
  reflexive {k = FZ} = FZ
  reflexive {k = FS k} = FS reflexive

  ||| Pointwise equality is symmetric
  export
  symmetric : k ~~~ l -> l ~~~ k
  symmetric FZ = FZ
  symmetric (FS prf) = FS (symmetric prf)

  ||| Pointwise equality is transitive
  export
  transitive : j ~~~ k -> k ~~~ l -> j ~~~ l
  transitive FZ FZ = FZ
  transitive (FS prf) (FS prg) = FS (transitive prf prg)

  ||| Pointwise equality is compatible with coerce
  export
  coerceEq : {k : Fin m} -> (0 eq : m = n) -> coerce eq k ~~~ k
  coerceEq {k = FZ} Refl = FZ
  coerceEq {k = FS k} Refl = FS (coerceEq _)

  ||| The actual proof used by coerce is irrelevant
  export
  congCoerce : {0 n, q : Nat} -> {k : Fin m} -> {l : Fin p} ->
               {0 eq1 : m = n} -> {0 eq2 : p = q} ->
               k ~~~ l ->
               coerce eq1 k ~~~ coerce eq2 l
  congCoerce eq
    = transitive (coerceEq _)
    $ transitive eq $ symmetric $ coerceEq _

  ||| Last is congruent wrt index equality
  export
  congLast : {m : Nat} -> (0 _ : m = n) -> last {n=m} ~~~ last {n}
  congLast Refl = reflexive

  export
  congShift : (m : Nat) -> k ~~~ l -> shift m k ~~~ shift m l
  congShift Z prf = prf
  congShift (S m) prf = FS (congShift m prf)

  ||| WeakenN is congruent wrt pointwise equality
  export
  congWeakenN : k ~~~ l -> weakenN n k ~~~ weakenN n l
  congWeakenN FZ = FZ
  congWeakenN (FS prf) = FS (congWeakenN prf)

  ||| Pointwise equality is propositional equality on Fins that have the same type
  export
  homoPointwiseIsEqual : {0 k, l : Fin m} -> k ~~~ l -> k === l
  homoPointwiseIsEqual FZ = Refl
  homoPointwiseIsEqual (FS prf) = cong FS (homoPointwiseIsEqual prf)

  ||| Pointwise equality is propositional equality modulo transport on Fins that
  ||| have provably equal types
  export
  hetPointwiseIsTransport :
     {0 k : Fin m} -> {0 l : Fin n} ->
     (0 eq : m === n) -> k ~~~ l -> k === rewrite eq in l
  hetPointwiseIsTransport Refl = homoPointwiseIsEqual

  export
  finToNatQuotient : k ~~~ l -> finToNat k === finToNat l
  finToNatQuotient FZ = Refl
  finToNatQuotient (FS prf) = cong S (finToNatQuotient prf)

  ||| Propositional equality on `finToNat`s implies pointwise equality on the `Fin`s themselves
  export
  finToNatEqualityAsPointwise : (k : Fin m) ->
                                (l : Fin n) ->
                                finToNat k = finToNat l ->
                                k ~~~ l
  finToNatEqualityAsPointwise FZ FZ _ = FZ
  finToNatEqualityAsPointwise FZ (FS _) prf = absurd prf
  finToNatEqualityAsPointwise (FS _) FZ prf = absurd prf
  finToNatEqualityAsPointwise (FS k) (FS l) prf = FS $ finToNatEqualityAsPointwise k l (injective prf)

  export
  weakenNeutral : (k : Fin n) -> weaken k ~~~ k
  weakenNeutral FZ = FZ
  weakenNeutral (FS k) = FS (weakenNeutral k)

  export
  weakenNNeutral : (0 m : Nat) -> (k : Fin n) -> weakenN m k ~~~ k
  weakenNNeutral m FZ = FZ
  weakenNNeutral m (FS k) = FS (weakenNNeutral m k)
