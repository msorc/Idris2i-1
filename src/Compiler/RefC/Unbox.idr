||| The variables of a function that the RefC backend keeps in C integers
||| (`int64_t`) instead of values (`Idris2_Value *`).
|||
||| An `Int` is a value like any other in RefC: a tagged pointer when it fits
||| in 32 bits, a box otherwise.  Every operation untags its arguments, and
||| tags (or boxes) its result after checking whether it fits.  In a loop on
||| `Int`s (a function calling itself in tail position, which jumps back to its
||| start) this is most of the work.  The variables chosen here are C integers
||| instead:
|||
||| * the parameters of type `Int` (or `Int64`, which RefC represents alike),
|||   which are unboxed once, when the function is called;
||| * the `let`s whose value is an operation on `Int`s, an `Int` literal, or a
|||   `case` whose branches give such values.
|||
||| Their uses must be operations on `Int`s, the scrutinee of a `case` on `Int`
||| literals, or a new value of a parameter that is a C integer too (in a call
||| of the function to itself).  Where a value is needed (the argument of
||| another function, a field of a constructor, the result) one is made from
||| the integer: this is allowed for the parameters of a loop (once an
||| iteration, as before), and for one use of a `let`.  Other uses (by a
||| foreign function, or a primitive taking values) keep the variable a value.
|||
||| The parameters are told from their types (in the context): the type of a
||| variable cannot be told from its uses, as it may depend on the value of
||| another argument (and it would be wrong to unbox it in the branches where it
||| is not an `Int`).
module Compiler.RefC.Unbox

import Compiler.ANF

import Core.Name
import Core.TT

import Data.List
import Data.SortedMap
import Data.SortedSet
import Data.Vect

%default covering

||| `Int` and `Int64`: RefC represents both by an `int64_t`.
export
isIntType : PrimType -> Bool
isIntType IntType = True
isIntType Int64Type = True
isIntType _ = False

||| The operations on `Int`s that give an `Int` (comparisons give 0 or 1).
export
intOp : PrimFn arity -> Bool
intOp (Add ty) = isIntType ty
intOp (Sub ty) = isIntType ty
intOp (Mul ty) = isIntType ty
intOp (Div ty) = isIntType ty
intOp (Mod ty) = isIntType ty
intOp (Neg ty) = isIntType ty
intOp (ShiftL ty) = isIntType ty
intOp (ShiftR ty) = isIntType ty
intOp (BAnd ty) = isIntType ty
intOp (BOr ty) = isIntType ty
intOp (BXOr ty) = isIntType ty
intOp (LT ty) = isIntType ty
intOp (LTE ty) = isIntType ty
intOp (EQ ty) = isIntType ty
intOp (GTE ty) = isIntType ty
intOp (GT ty) = isIntType ty
intOp _ = False

||| Is the result of an operation on `Int`s a Boolean (a comparison), which
||| RefC makes with `idris2_mkBool`?
export
isComparison : PrimFn arity -> Bool
isComparison (LT _) = True
isComparison (LTE _) = True
isComparison (EQ _) = True
isComparison (GTE _) = True
isComparison (GT _) = True
isComparison _ = False

wrapping : String -> String -> String -> String
wrapping op x y = "((int64_t)((uint64_t)(\{x}) \{op} (uint64_t)(\{y})))"

||| The C expression of an operation on `Int`s (see `intOp`), of C integers.
||| It computes what the macros of mathFunctions.h compute on values: the
||| arithmetic wraps around (it is done on unsigned integers), `div` and
||| `mod` are Euclidean, and the shifts are those of the Scheme backends.
export
intOpC : PrimFn arity -> Vect arity String -> String
intOpC (Add _) [x, y] = wrapping "+" x y
intOpC (Sub _) [x, y] = wrapping "-" x y
intOpC (Mul _) [x, y] = wrapping "*" x y
intOpC (Div _) [x, y] = "idris2_euclidDiv_Int64(\{x}, \{y})"
intOpC (Mod _) [x, y] = "idris2_euclidMod_Int64(\{x}, \{y})"
intOpC (Neg _) [x] = "((int64_t)(0u - (uint64_t)(\{x})))"
intOpC (ShiftL _) [x, y] = "idris2_shiftLeft_Int64(\{x}, \{y})"
intOpC (ShiftR _) [x, y] = "idris2_shiftRight_Int64(\{x}, \{y})"
intOpC (BAnd _) [x, y] = "((\{x}) & (\{y}))"
intOpC (BOr _) [x, y] = "((\{x}) | (\{y}))"
intOpC (BXOr _) [x, y] = "((\{x}) ^ (\{y}))"
intOpC (LT _) [x, y] = "((\{x}) < (\{y}))"
intOpC (LTE _) [x, y] = "((\{x}) <= (\{y}))"
intOpC (EQ _) [x, y] = "((\{x}) == (\{y}))"
intOpC (GTE _) [x, y] = "((\{x}) >= (\{y}))"
intOpC (GT _) [x, y] = "((\{x}) > (\{y}))"
intOpC op _ = "/* not an operation on Ints: \{show op} */"

||| Is a `case` on these constants a `switch` on an `Int` (see `unboxConst` in
||| RefC)?
export
intAlts : List AConstAlt -> Bool
intAlts = all (\(MkAConstAlt c _) => isIntConst c)
  where
    isIntConst : Constant -> Bool
    isIntConst (I _) = True
    isIntConst (I64 _) = True
    isIntConst _ = False

||| How the code generator uses a variable.
data Use
  = ||| as an operand of an operation on `Int`s, or the scrutinee of a `case`
    ||| on `Int` literals
    Numeric
  | ||| as a value (`avarToC`): one can be made from a C integer
    Boxed
  | ||| as it is: it must be a value
    Raw
  | ||| as the new value of a parameter (by its position), in a call of the
    ||| function to itself (`selfTailCall`)
    SelfArg Nat

Uses : Type
Uses = SortedMap Int (List Use)

addUse : Use -> AVar -> Uses -> Uses
addUse u (ALocal i) us = insert i (u :: fromMaybe [] (lookup i us)) us
addUse _ ANull us = us

addUses : Use -> List AVar -> Uses -> Uses
addUses u vs us = foldl (flip (addUse u)) us vs

||| How the calls are made.
public export
record Calls where
  constructor MkCalls
  ||| Is this call in tail position one of the function to itself, which
  ||| jumps back to its start (see `makeTailCall`)?
  isSelf : Name -> List AVar -> Bool
  ||| Is it a call of a foreign function, which takes the variables as they
  ||| are (see `foreignCall`)?
  isForeign : Name -> List AVar -> Bool

usesIn : Calls -> (tail : Bool) -> ANF -> Uses -> Uses
usesIn c t (AV _ v) us = addUse Boxed v us
usesIn c t (AAppName _ _ n args) us
    = if c.isForeign n args then addUses Raw args us
      else if t && c.isSelf n args
         then foldl (\us', (k, a) => addUse (SelfArg k) a us') us
                    (zip [0 .. length args] args)
         else addUses Boxed args us
usesIn c t (AUnderApp _ _ _ args) us = addUses Boxed args us
usesIn c t (AApp _ _ f a) us = addUse Boxed f (addUse Boxed a us)
usesIn c t (ALet _ _ val body) us = usesIn c t body (usesIn c False val us)
usesIn c t (ACon _ _ _ _ args) us = addUses Boxed args us
usesIn c t (AOp _ _ op args) us
    = addUses (if intOp op then Numeric else Raw) (toList args) us
usesIn c t (AExtPrim _ _ _ args) us = addUses Raw args us
usesIn c t (AConCase _ sc alts def) us
    = let us = foldl (\us', (MkAConAlt _ _ _ _ b) => usesIn c t b us') us alts
          us = maybe us (\d => usesIn c t d us) def in
          addUse Raw sc us
usesIn c t (AConstCase _ sc alts def) us
    = let us = foldl (\us', (MkAConstAlt _ b) => usesIn c t b us') us alts
          us = maybe us (\d => usesIn c t d us) def in
          case alts of
               [] => us -- (only a default: the scrutinee is not looked at)
               _ => addUse (if intAlts alts then Numeric else Raw) sc us
usesIn _ _ _ us = us

||| Does the expression have an operation on `Int`s?  Without one, no variable
||| is worth unboxing (and the types of the parameters need not be looked up).
export
hasIntOp : ANF -> Bool
hasIntOp (AOp _ _ op _) = intOp op
hasIntOp (ALet _ _ val body) = hasIntOp val || hasIntOp body
hasIntOp (AConCase _ _ alts def)
    = any (\(MkAConAlt _ _ _ _ b) => hasIntOp b) alts || any hasIntOp def
hasIntOp (AConstCase _ _ alts def)
    = any (\(MkAConstAlt _ b) => hasIntOp b) alts || any hasIntOp def
hasIntOp _ = False

||| The values of the `let`s.
letValues : ANF -> SortedMap Int ANF -> SortedMap Int ANF
letValues (ALet _ v val body) ls = letValues body (letValues val (insert v val ls))
letValues (AConCase _ _ alts def) ls
    = let ls = foldl (\ls', (MkAConAlt _ _ _ _ b) => letValues b ls') ls alts in
          maybe ls (\d => letValues d ls) def
letValues (AConstCase _ _ alts def) ls
    = let ls = foldl (\ls', (MkAConstAlt _ b) => letValues b ls') ls alts in
          maybe ls (\d => letValues d ls) def
letValues _ ls = ls

||| Can the expression be compiled to a C integer (see `cIntFromANF` in RefC),
||| given the variables that are C integers?
export
intValued : SortedSet Int -> ANF -> Bool
intValued u (AOp _ _ op _) = intOp op
intValued u (APrimVal _ (I _)) = True
intValued u (APrimVal _ (I64 _)) = True
intValued u (AV _ (ALocal v)) = contains v u
intValued u (ALet _ _ _ body) = intValued u body
intValued u (AConstCase _ _ alts def)
    = all (\(MkAConstAlt _ b) => intValued u b) alts && all (intValued u) def
intValued u (ACrash _ _) = True
intValued _ _ = False

||| The variables of a function (its parameters `params`, of which those of
||| type `Int` are `intParams`, and the `let`s of its body) to keep in C
||| integers.  `loops` tells whether the function calls itself in tail
||| position.
export
unboxedVars : Calls -> (loops : Bool) -> (params : List Int) ->
              (intParams : SortedSet Int) -> ANF -> SortedSet Int
unboxedVars c loops params ips body
    -- (`us` and `lets` are computed once: as definitions of the `where`
    -- block, they would be computed at each use.)
    = let us = usesIn c True body empty
          lets = letValues body empty in
          if null (keys lets) && null (filter (`contains` ips) params)
             then empty
             else keep us lets (fromList (filter (`contains` ips) params ++ keys lets))
  where
    paramAt : Nat -> List Int -> Maybe Int
    paramAt _ [] = Nothing
    paramAt Z (p :: _) = Just p
    paramAt (S k) (_ :: ps) = paramAt k ps

    -- a use as an integer, given the variables that are C integers
    numeric : SortedSet Int -> Use -> Bool
    numeric u Numeric = True
    numeric u (SelfArg k) = maybe False (`contains` u) (paramAt k params)
    numeric u _ = False

    -- a use as a value, which needs one to be made
    boxed : SortedSet Int -> Use -> Bool
    boxed u Boxed = True
    boxed u (SelfArg k) = not (numeric u (SelfArg k))
    boxed u _ = False

    isRaw : Use -> Bool
    isRaw Raw = True
    isRaw _ = False

    isNumeric : Use -> Bool
    isNumeric Numeric = True
    isNumeric _ = False

    ok : Uses -> SortedMap Int ANF -> SortedSet Int -> Int -> Bool
    ok us lets u v
        = let vs = fromMaybe [] (lookup v us) in
          not (any isRaw vs) &&
          case lookup v lets of
               Just val => intValued u val
                           && any (numeric u) vs
                           && length (filter (boxed u) vs) <= 1
               -- a parameter: passing it on to itself is not a reason (it
               -- would only be unboxed and boxed again)
               Nothing => any isNumeric vs
                          && (loops || not (any (boxed u) vs))

    -- The variables are removed until those left are all fine with each
    -- other (a parameter and the `let` giving its next value, for example).
    keep : Uses -> SortedMap Int ANF -> SortedSet Int -> SortedSet Int
    keep us lets u
        = let vs = Prelude.toList u
              vs' = filter (ok us lets u) vs in
              if length vs' == length vs
                 then u
                 else keep us lets (fromList vs')
