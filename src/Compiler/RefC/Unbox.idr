||| The variables of a function that the RefC backend keeps in C integers
||| (`int64_t`, `uint8_t`, ...) instead of values (`Idris2_Value *`).
|||
||| A fixed width integer is a value like any other in RefC: a tagged pointer
||| when it fits in 32 bits, a box otherwise (`Int`, `Int64` and `Bits64`
||| beyond 32 bits, and `Int32` and `Bits32` on 32 bit platforms).  Every
||| operation untags its arguments, and tags (or boxes) its result after
||| checking whether it fits.  In a loop (a function calling itself in tail
||| position, which jumps back to its start) this is most of the work, and a
||| hash or a checksum on `Bits64` allocates at every step.  The variables
||| chosen here are C integers of their type instead:
|||
||| * the parameters of a fixed width integer type (`Int`, `Int8` to `Int64`,
|||   `Bits8` to `Bits64`), which are unboxed once, when the function is
|||   called;
||| * the `let`s whose value is an operation giving such an integer (or a
|||   comparison of them), a literal, or a `case` whose branches give such
|||   values.
|||
||| Their uses must be operations on integers of their type, the scrutinee of
||| a `case` on literals of their type, or a new value of a parameter that is
||| a C integer of the same type (in a call of the function to itself).  Where
||| a value is needed (the argument of another function, a field of a
||| constructor, the result) one is made from the integer: this is allowed for
||| the parameters of a loop (once an iteration, as before), and for one use of
||| a `let`.  Other uses (by a foreign function, or a primitive taking values)
||| keep the variable a value.
|||
||| The parameters are told from their types (in the context): the type of a
||| variable cannot be told from its uses, as it may depend on the value of
||| another argument (and it would be wrong to unbox it in the branches where it
||| is not an integer).  The uses must agree with that type: after
||| `believe_me` a variable may be used at another type, and then it is left a
||| value.
module Compiler.RefC.Unbox

import Compiler.ANF

import Core.Name
import Core.TT

import Data.List
import Data.SortedMap
import Data.SortedSet
import Data.Vect

%default covering

||| The type of the C integers of a fixed width integer type, if it is one.
||| `Int` and `Int64` are alike in RefC (an `int64_t`): both are `IntType`.
export
unboxedType : PrimType -> Maybe PrimType
unboxedType IntType = Just IntType
unboxedType Int64Type = Just IntType
unboxedType Int8Type = Just Int8Type
unboxedType Int16Type = Just Int16Type
unboxedType Int32Type = Just Int32Type
unboxedType Bits8Type = Just Bits8Type
unboxedType Bits16Type = Just Bits16Type
unboxedType Bits32Type = Just Bits32Type
unboxedType Bits64Type = Just Bits64Type
unboxedType _ = Nothing

||| The C type of the integers of an unboxed type (see `unboxedType`).
export
cIntType : PrimType -> String
cIntType Int8Type = "int8_t"
cIntType Int16Type = "int16_t"
cIntType Int32Type = "int32_t"
cIntType Bits8Type = "uint8_t"
cIntType Bits16Type = "uint16_t"
cIntType Bits32Type = "uint32_t"
cIntType Bits64Type = "uint64_t"
cIntType _ = "int64_t"

||| The name of the type in the runtime (`idris2_mkBits8`, ...).
export
runtimeName : PrimType -> String
runtimeName Int8Type = "Int8"
runtimeName Int16Type = "Int16"
runtimeName Int32Type = "Int32"
runtimeName Bits8Type = "Bits8"
runtimeName Bits16Type = "Bits16"
runtimeName Bits32Type = "Bits32"
runtimeName Bits64Type = "Bits64"
runtimeName _ = "Int64"

isSigned : PrimType -> Bool
isSigned Bits8Type = False
isSigned Bits16Type = False
isSigned Bits32Type = False
isSigned Bits64Type = False
isSigned _ = True

||| The number of bits of an unboxed type.
width : PrimType -> Nat
width Int8Type = 8
width Int16Type = 16
width Int32Type = 32
width Bits8Type = 8
width Bits16Type = 16
width Bits32Type = 32
width _ = 64

||| A new value (that the caller owns) made from a C integer of the type.
export
boxC : PrimType -> String -> String
boxC t e = "idris2_mk\{runtimeName t}(\{e})"

||| The C integer of a value of the type (which stays borrowed).
export
unboxC : PrimType -> String -> String
unboxC t v = "idris2_vp_to_\{runtimeName t}(\{v})"

||| The types to which the casts from fixed width integers are done on C
||| integers too (their results are values).
castTarget : PrimType -> Bool
castTarget DoubleType = True
castTarget CharType = True
castTarget IntegerType = True
castTarget _ = False

||| The type of the C integers that an operation takes, if it is done on C
||| integers: the arithmetic, bitwise operations and comparisons on fixed
||| width integers, and the casts from them to fixed width integers, `Double`,
||| `Char` and `Integer`.
export
operandType : PrimFn arity -> Maybe PrimType
operandType (Add ty) = unboxedType ty
operandType (Sub ty) = unboxedType ty
operandType (Mul ty) = unboxedType ty
operandType (Div ty) = unboxedType ty
operandType (Mod ty) = unboxedType ty
operandType (Neg ty) = unboxedType ty
operandType (ShiftL ty) = unboxedType ty
operandType (ShiftR ty) = unboxedType ty
operandType (BAnd ty) = unboxedType ty
operandType (BOr ty) = unboxedType ty
operandType (BXOr ty) = unboxedType ty
operandType (LT ty) = unboxedType ty
operandType (LTE ty) = unboxedType ty
operandType (EQ ty) = unboxedType ty
operandType (GTE ty) = unboxedType ty
operandType (GT ty) = unboxedType ty
operandType (Cast from to)
    = if isJust (unboxedType to) || castTarget to then unboxedType from else Nothing
operandType _ = Nothing

||| The type of the C integer that an operation gives, if it can give one:
||| those of `operandType` with a fixed width integer result (a comparison
||| gives an `Int`, 0 or 1), and the casts from `Double`, `Char` and `Integer`
||| to fixed width integers (which take values).
export
resultType : PrimFn arity -> Maybe PrimType
resultType (LT ty) = map (const IntType) (unboxedType ty)
resultType (LTE ty) = map (const IntType) (unboxedType ty)
resultType (EQ ty) = map (const IntType) (unboxedType ty)
resultType (GTE ty) = map (const IntType) (unboxedType ty)
resultType (GT ty) = map (const IntType) (unboxedType ty)
resultType (Cast from to)
    = if isJust (unboxedType from) || castTarget from then unboxedType to else Nothing
resultType op = operandType op

||| Is the result of an operation a Boolean (a comparison), which RefC makes
||| with `idris2_mkBool`?
export
isComparison : PrimFn arity -> Bool
isComparison (LT _) = True
isComparison (LTE _) = True
isComparison (EQ _) = True
isComparison (GTE _) = True
isComparison (GT _) = True
isComparison _ = False

-- (the arithmetic is done on `uint64_t`, where it wraps around, and the
-- result converted to the type: a C compiler does it in the width of the
-- type, without undefined behaviour for the signed types)
wrapping : PrimType -> String -> String -> String -> String
wrapping t op x y = "((\{cIntType t})((uint64_t)(\{x}) \{op} (uint64_t)(\{y})))"

||| The C expression of an operation of `operandType` or `resultType`.  Its
||| operands are C integers of the `operandType`, or values for the casts
||| from `Double`, `Char` and `Integer`; it is a C integer of the
||| `resultType`, or a new value for the casts to `Double`, `Char` and
||| `Integer`.  It computes what the macros of mathFunctions.h and casts.h
||| compute on values: the arithmetic wraps around, the signed `div` and `mod`
||| are Euclidean, the shifts are those of the Scheme backends.
export
intOpC : PrimFn arity -> Vect arity String -> String
intOpC (Add ty) [x, y] = wrapping ty "+" x y
intOpC (Sub ty) [x, y] = wrapping ty "-" x y
intOpC (Mul ty) [x, y] = wrapping ty "*" x y
intOpC (Div ty) [x, y]
    = if isSigned ty then "idris2_euclidDiv_\{runtimeName ty}(\{x}, \{y})"
                     else "idris2_unsignedDiv_\{runtimeName ty}(\{x}, \{y})"
intOpC (Mod ty) [x, y]
    = if isSigned ty then "idris2_euclidMod_\{runtimeName ty}(\{x}, \{y})"
                     else "idris2_unsignedMod_\{runtimeName ty}(\{x}, \{y})"
intOpC (Neg ty) [x] = "((\{cIntType ty})(0u - (uint64_t)(\{x})))"
intOpC (ShiftL ty) [x, y] = "idris2_shiftLeft_\{runtimeName ty}(\{x}, \{y})"
intOpC (ShiftR ty) [x, y] = "idris2_shiftRight_\{runtimeName ty}(\{x}, \{y})"
intOpC (BAnd ty) [x, y] = "((\{cIntType ty})((\{x}) & (\{y})))"
intOpC (BOr ty) [x, y] = "((\{cIntType ty})((\{x}) | (\{y})))"
intOpC (BXOr ty) [x, y] = "((\{cIntType ty})((\{x}) ^ (\{y})))"
intOpC (LT _) [x, y] = "((\{x}) < (\{y}))"
intOpC (LTE _) [x, y] = "((\{x}) <= (\{y}))"
intOpC (EQ _) [x, y] = "((\{x}) == (\{y}))"
intOpC (GTE _) [x, y] = "((\{x}) >= (\{y}))"
intOpC (GT _) [x, y] = "((\{x}) > (\{y}))"
intOpC (Cast from to) [x] = case (unboxedType from, unboxedType to) of
    (Just _, Just t) => "((\{cIntType t})(\{x}))"
    (Just f, Nothing) => case to of
        DoubleType => "idris2_mkDouble((double)(\{x}))"
        CharType => "idris2_mkValidChar(\{x})"
        _ => if isSigned f then "idris2_mkIntegerFromInt64(\{x})"
                           else "idris2_mkIntegerFromUInt64(\{x})"
    (Nothing, Just t) => case from of
        DoubleType => "((\{cIntType t})idris2_double_to_wrapped(idris2_vp_to_Double(\{x})))"
        CharType => "((\{cIntType t})idris2_vp_to_Char(\{x}))"
        _ => "((\{cIntType t})idris2_integerLow64(\{x}))"
    _ => "/* not a cast of fixed width integers: \{show from} to \{show to} */"
intOpC op _ = "/* not an operation on fixed width integers: \{show op} */"

||| The unboxed type of a literal, if it is a fixed width integer.
export
constType : Constant -> Maybe PrimType
constType (I _) = Just IntType
constType (I64 _) = Just IntType
constType (I8 _) = Just Int8Type
constType (I16 _) = Just Int16Type
constType (I32 _) = Just Int32Type
constType (B8 _) = Just Bits8Type
constType (B16 _) = Just Bits16Type
constType (B32 _) = Just Bits32Type
constType (B64 _) = Just Bits64Type
constType _ = Nothing

||| The C constant of a fixed width integer literal (C does not allow
||| `-9223372036854775808`).
export
cIntLiteral : Constant -> String
cIntLiteral (I x) = if x == -9223372036854775808 then "INT64_MIN" else "INT64_C(\{show x})"
cIntLiteral (I64 x) = if x == -9223372036854775808 then "INT64_MIN" else "INT64_C(\{show x})"
cIntLiteral (I8 x) = "INT8_C(\{show x})"
cIntLiteral (I16 x) = "INT16_C(\{show x})"
cIntLiteral (I32 x) = "INT32_C(\{show x})"
cIntLiteral (B8 x) = "UINT8_C(\{show x})"
cIntLiteral (B16 x) = "UINT16_C(\{show x})"
cIntLiteral (B32 x) = "UINT32_C(\{show x})"
cIntLiteral (B64 x) = "UINT64_C(\{show x})"
cIntLiteral c = "/* not a fixed width integer: \{show c} */"

||| The type of the literals of a `case`, if they are all fixed width integers
||| of one type (it is then a `switch` on C integers of that type, see
||| `unboxConst` in RefC).
export
altsType : List AConstAlt -> Maybe PrimType
altsType [] = Nothing
altsType (MkAConstAlt c _ :: alts)
    = do t <- constType c
         if all (\(MkAConstAlt c' _) => constType c' == Just t) alts
            then Just t else Nothing

||| How the code generator uses a variable.
data Use
  = ||| as an operand of an operation on C integers of the type, or the
    ||| scrutinee of a `case` on literals of the type
    Numeric PrimType
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
    = addUses (maybe Raw Numeric (operandType op)) (toList args) us
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
               _ => addUse (maybe Raw Numeric (altsType alts)) sc us
usesIn _ _ _ us = us

||| Does the expression have an operation on C integers?  Without one, no
||| variable is worth unboxing (and the types of the parameters need not be
||| looked up).
export
hasIntOp : ANF -> Bool
hasIntOp (AOp _ _ op _) = isJust (operandType op) || isJust (resultType op)
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

||| The type of the C integer that an expression can be compiled to (see
||| `cIntFromANF` in RefC), given the variables that are C integers, if it
||| can be.
export
valueType : SortedMap Int PrimType -> ANF -> Maybe PrimType
valueType u e = case go e of
                     Just (Just t) => Just t
                     _ => Nothing
  where
    -- `Just Nothing`: any type (a crash)
    go : ANF -> Maybe (Maybe PrimType)
    go (AOp _ _ op _) = map Just (resultType op)
    go (APrimVal _ c) = map Just (constType c)
    go (AV _ (ALocal v)) = map Just (lookup v u)
    go (ALet _ _ _ body) = go body
    go (AConstCase _ _ alts def)
        = do ts <- traverse (\(MkAConstAlt _ b) => go b) alts
             d <- traverse go def
             let known = catMaybes (maybe ts (:: ts) d)
             case known of
                  [] => Just Nothing
                  (t :: rest) => if all (== t) rest then Just (Just t) else Nothing
    go (ACrash _ _) = Just Nothing
    go _ = Nothing

||| The variables of a function (its parameters `params`, of which those of
||| fixed width integer types are `intParams`, with their unboxed types, and
||| the `let`s of its body) to keep in C integers, with their types.  `loops`
||| tells whether the function calls itself in tail position.
export
unboxedVars : Calls -> (loops : Bool) -> (params : List Int) ->
              (intParams : SortedMap Int PrimType) -> ANF -> SortedMap Int PrimType
unboxedVars c loops params ips body
    -- (`us` and `lets` are computed once: as definitions of the `where`
    -- block, they would be computed at each use.)
    = let us = usesIn c True body empty
          lets = letValues body empty
          ps = mapMaybe (\p => map (p,) (lookup p ips)) params in
          if null (keys lets) && null ps
             then empty
             else keep us lets (candidates (SortedMap.toList lets) (fromList ps))
  where
    -- The parameters, and the `let`s whose values can be C integers if the
    -- variables found so far are (a `let` may be a copy of another one).
    candidates : List (Int, ANF) -> SortedMap Int PrimType -> SortedMap Int PrimType
    candidates ls u
        = let new = mapMaybe (\(v, val) => if isJust (lookup v u) then Nothing
                                             else map (v,) (valueType u val)) ls in
              if null new then u else candidates ls (mergeLeft u (fromList new))

    paramAt : Nat -> List Int -> Maybe Int
    paramAt _ [] = Nothing
    paramAt Z (p :: _) = Just p
    paramAt (S k) (_ :: ps) = paramAt k ps

    -- a use as an integer of the type `t`, given the variables that are C
    -- integers
    numeric : SortedMap Int PrimType -> PrimType -> Use -> Bool
    numeric u t (Numeric t') = t == t'
    numeric u t (SelfArg k) = maybe False (\p => lookup p u == Just t) (paramAt k params)
    numeric u t _ = False

    -- a use as a value, which needs one to be made
    boxed : SortedMap Int PrimType -> PrimType -> Use -> Bool
    boxed u t Boxed = True
    boxed u t (SelfArg k) = not (numeric u t (SelfArg k))
    boxed u t _ = False

    -- a use that needs the value as it is (or as an integer of another type)
    raw : PrimType -> Use -> Bool
    raw t Raw = True
    raw t (Numeric t') = t /= t'
    raw t _ = False

    isNumeric : PrimType -> Use -> Bool
    isNumeric t (Numeric t') = t == t'
    isNumeric _ _ = False

    ok : Uses -> SortedMap Int ANF -> SortedMap Int PrimType -> (Int, PrimType) -> Bool
    ok us lets u (v, t)
        = let vs = fromMaybe [] (lookup v us) in
          not (any (raw t) vs) &&
          case lookup v lets of
               Just val => valueType u val == Just t
                           && any (numeric u t) vs
                           && length (filter (boxed u t) vs) <= 1
               -- a parameter: passing it on to itself is not a reason (it
               -- would only be unboxed and boxed again)
               Nothing => any (isNumeric t) vs
                          && (loops || not (any (boxed u t) vs))

    -- The variables are removed until those left are all fine with each
    -- other (a parameter and the `let` giving its next value, for example).
    keep : Uses -> SortedMap Int ANF -> SortedMap Int PrimType -> SortedMap Int PrimType
    keep us lets u
        = let vs = SortedMap.toList u
              vs' = filter (ok us lets u) vs in
              if length vs' == length vs
                 then u
                 else keep us lets (fromList vs')

||| The literal of the type `t` that the cast of the Integer `x` gives: the
||| Integer is wrapped around to the width of the type, as the casts of the
||| runtime do (`idris2_cast_Integer_to_Bits8`, ...).  This is computed on
||| Integers, so it does not depend on the machine that runs the compiler.
export
castIntegerLiteral : PrimType -> Integer -> Maybe Constant
castIntegerLiteral t x
    = do u <- unboxedType t
         let m = pow2 (width u)
         let r = x `mod` m
         let r = if r < 0 then r + m else r
         let s = if isSigned u && r >= m `div` 2 then r - m else r
         pure $ case t of
           IntType => I (cast s)
           Int64Type => I64 (cast s)
           Int8Type => I8 (cast s)
           Int16Type => I16 (cast s)
           Int32Type => I32 (cast s)
           Bits8Type => B8 (cast s)
           Bits16Type => B16 (cast s)
           Bits32Type => B32 (cast s)
           _ => B64 (cast s)
  where
    pow2 : Nat -> Integer
    pow2 Z = 1
    pow2 (S k) = 2 * pow2 k

||| The casts of Integer literals to fixed width integers are made literals of
||| those types: the constant folding leaves those to `Int` of more than 32
||| bits, as the width of `Int` depends on the backend (it is 64 bits in
||| RefC).  Without this, `0xffffffff : Int` would make an Integer and convert
||| it every time it is computed.  The `let`s of the Integers that are then
||| unused are removed.
export
foldIntegerCasts : ANF -> ANF
foldIntegerCasts e
    = let others = otherUses e empty in
          go others empty e
  where
    foldable : PrimFn arity -> Bool
    foldable (Cast IntegerType t) = isJust (unboxedType t)
    foldable _ = False

    vars : List AVar -> SortedSet Int -> SortedSet Int
    vars as s = foldl (\s', a => case a of
                                     ALocal i => insert i s'
                                     ANull => s') s as

    -- The variables with a use other than a cast to a fixed width integer.
    otherUses : ANF -> SortedSet Int -> SortedSet Int
    otherUses (AV _ v) s = vars [v] s
    otherUses (AAppName _ _ _ as) s = vars as s
    otherUses (AUnderApp _ _ _ as) s = vars as s
    otherUses (AApp _ _ f a) s = vars [f, a] s
    otherUses (ALet _ _ val body) s = otherUses body (otherUses val s)
    otherUses (ACon _ _ _ _ as) s = vars as s
    otherUses (AOp _ _ op as) s = if foldable op then s else vars (toList as) s
    otherUses (AExtPrim _ _ _ as) s = vars as s
    otherUses (AConCase _ sc alts def) s
        = let s = foldl (\s', (MkAConAlt _ _ _ _ b) => otherUses b s') (vars [sc] s) alts in
              maybe s (\d => otherUses d s) def
    otherUses (AConstCase _ sc alts def) s
        = let s = foldl (\s', (MkAConstAlt _ b) => otherUses b s') (vars [sc] s) alts in
              maybe s (\d => otherUses d s) def
    otherUses _ s = s

    go : SortedSet Int -> SortedMap Int Integer -> ANF -> ANF
    go others ls (ALet fc v val@(APrimVal _ (BI x)) body)
        = let body' = go others (insert v x ls) body in
              if contains v others then ALet fc v val body' else body'
    go others ls (ALet fc v val body) = ALet fc v (go others ls val) (go others ls body)
    go others ls e@(AOp fc _ (Cast IntegerType t) [ALocal v])
        = fromMaybe e $ do x <- lookup v ls
                           c <- castIntegerLiteral t x
                           pure (APrimVal fc c)
    go others ls (AConCase fc sc alts def)
        = AConCase fc sc (map (\(MkAConAlt n ci t as b) => MkAConAlt n ci t as (go others ls b)) alts)
                   (map (go others ls) def)
    go others ls (AConstCase fc sc alts def)
        = AConstCase fc sc (map (\(MkAConstAlt c b) => MkAConstAlt c (go others ls b)) alts)
                     (map (go others ls) def)
    go _ _ e = e
