||| The variables of a function that the RefC backend keeps in C integers
||| (`int64_t`, `uint8_t`, ...) instead of values (`Idris2i_1_Value *`).
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
||| Across the functions: a function whose parameters (or result) are C
||| integers has a worker that takes (or gives) them as such (see `Worker` in
||| Compiler.RefC.RefC).  An argument of such a parameter, in a call of the
||| function by name, is used as an integer of its type; the result of such a
||| call is an integer of its type.  So the variables found depend on the
||| workers of the functions called, which depend on the variables found in
||| them: the analysis is made again for the callers of the functions whose
||| workers changed (`unboxedProgram` in RefC).  A worker may also return a
||| parameter that it takes as a C integer (`Returned`): its callers pass the
||| integer.
|||
||| The parameters are told from their types (in the context): the type of a
||| variable cannot be told from its uses, as it may depend on the value of
||| another argument (and it would be wrong to unbox it in the branches where it
||| is not an integer).  The uses must agree with that type: after
||| `believe_me` a variable may be used at another type, and then it is left a
||| value.
module Compiler.RefC.Unbox

import Compiler.ANF
import Compiler.RefC.FlatOpt

import Core.Name
import Core.TT

import Data.List
import Data.String
import Data.SortedMap
import Data.SortedSet
import Data.Vect

%default covering

||| The type of the C numbers of a fixed width integer type or of `Double`, if
||| it is one.  `Int` and `Int64` are alike in RefC (an `int64_t`): both are
||| `IntType`.  (A `Double` is a C `double`: the "C integers" of this module
||| and of RefC are the C numbers of these types, `double` included.  It is
||| never stored in an `Idris2i_1_Value *`, so it need not fit in a pointer.)
export
unboxedType : PrimType -> Maybe PrimType
unboxedType DoubleType = Just DoubleType
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
cIntType DoubleType = "double"
cIntType _ = "int64_t"

||| The name of the type in the runtime (`idris2i_1_mkBits8`, ...).
export
runtimeName : PrimType -> String
runtimeName Int8Type = "Int8"
runtimeName Int16Type = "Int16"
runtimeName Int32Type = "Int32"
runtimeName Bits8Type = "Bits8"
runtimeName Bits16Type = "Bits16"
runtimeName Bits32Type = "Bits32"
runtimeName Bits64Type = "Bits64"
runtimeName DoubleType = "Double"
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
boxC t e = "idris2i_1_mk\{runtimeName t}(\{e})"

||| The C integer of a value of the type (which stays borrowed).
export
unboxC : PrimType -> String -> String
unboxC t v = "idris2i_1_vp_to_\{runtimeName t}(\{v})"

||| The types to which the casts from C numbers are done on C numbers too
||| (their results are values).
castTarget : PrimType -> Bool
castTarget CharType = True
castTarget IntegerType = True
castTarget _ = False

||| The type of the C numbers that an operation takes, if it is done on C
||| numbers: the arithmetic, bitwise operations and comparisons on fixed
||| width integers, the arithmetic, comparisons and functions of `Double`
||| (but `mod` and the bitwise operations, which it does not have), and the
||| casts from them to fixed width integers, `Double`, `Char` and `Integer`.
export
operandType : PrimFn arity -> Maybe PrimType
operandType (Mod DoubleType) = Nothing
operandType (ShiftL DoubleType) = Nothing
operandType (ShiftR DoubleType) = Nothing
operandType (BAnd DoubleType) = Nothing
operandType (BOr DoubleType) = Nothing
operandType (BXOr DoubleType) = Nothing
operandType DoubleExp = Just DoubleType
operandType DoubleLog = Just DoubleType
operandType DoublePow = Just DoubleType
operandType DoubleSin = Just DoubleType
operandType DoubleCos = Just DoubleType
operandType DoubleTan = Just DoubleType
operandType DoubleASin = Just DoubleType
operandType DoubleACos = Just DoubleType
operandType DoubleATan = Just DoubleType
operandType DoubleSqrt = Just DoubleType
operandType DoubleFloor = Just DoubleType
operandType DoubleCeiling = Just DoubleType
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

||| The type of the C number that an operation gives, if it can give one:
||| those of `operandType` with a result of a fixed width integer type or
||| `Double` (a comparison gives an `Int`, 0 or 1), and the casts from `Char`
||| and `Integer` to these types (which take values).
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
||| with `idris2i_1_mkBool`?
export
isComparison : PrimFn arity -> Bool
isComparison (LT _) = True
isComparison (LTE _) = True
isComparison (EQ _) = True
isComparison (GTE _) = True
isComparison (GT _) = True
isComparison _ = False

-- The C function of a function of `Double` (see `cOp` in RefC).
doubleFn : PrimFn arity -> Maybe String
doubleFn DoubleExp = Just "exp"
doubleFn DoubleLog = Just "log"
doubleFn DoublePow = Just "pow"
doubleFn DoubleSin = Just "sin"
doubleFn DoubleCos = Just "cos"
doubleFn DoubleTan = Just "tan"
doubleFn DoubleASin = Just "asin"
doubleFn DoubleACos = Just "acos"
doubleFn DoubleATan = Just "atan"
doubleFn DoubleSqrt = Just "sqrt"
doubleFn DoubleFloor = Just "floor"
doubleFn DoubleCeiling = Just "ceil"
doubleFn _ = Nothing

||| The C expression of an operation on C doubles, as mathFunctions.h, casts.h
||| and `cOp` in RefC compute it on values: the arithmetic and comparisons of
||| C, which give what IEEE 754 says for NaN, the infinities and the signed
||| zeros.  A result is rounded to a double, as it is in a value, where the C
||| compiler would keep more precision (IDRIS2I_1_DOUBLE, see mathFunctions.h).
doubleOpC : PrimFn arity -> Vect arity String -> String
doubleOpC (Add _) [x, y] = "IDRIS2I_1_DOUBLE((\{x}) + (\{y}))"
doubleOpC (Sub _) [x, y] = "IDRIS2I_1_DOUBLE((\{x}) - (\{y}))"
doubleOpC (Mul _) [x, y] = "IDRIS2I_1_DOUBLE((\{x}) * (\{y}))"
doubleOpC (Div _) [x, y] = "IDRIS2I_1_DOUBLE((\{x}) / (\{y}))"
doubleOpC (Neg _) [x] = "(-(\{x}))"
doubleOpC (LT _) [x, y] = "((\{x}) < (\{y}))"
doubleOpC (LTE _) [x, y] = "((\{x}) <= (\{y}))"
doubleOpC (EQ _) [x, y] = "((\{x}) == (\{y}))"
doubleOpC (GTE _) [x, y] = "((\{x}) >= (\{y}))"
doubleOpC (GT _) [x, y] = "((\{x}) > (\{y}))"
doubleOpC DoublePow [x, y] = "IDRIS2I_1_DOUBLE(pow(\{x}, \{y}))"
doubleOpC op [x] = maybe "/* not an operation on doubles: \{show op} */"
                         (\f => "IDRIS2I_1_DOUBLE(\{f}(\{x}))") (doubleFn op)
doubleOpC op _ = "/* not an operation on doubles: \{show op} */"

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
-- (a cast from or to Double first: the others are those of the integers)
intOpC (Cast DoubleType to) [x] = case unboxedType to of
    Just t => "((\{cIntType t})idris2i_1_double_to_wrapped(\{x}))"
    Nothing => case to of
        CharType => "idris2i_1_mkValidChar(idris2i_1_double_to_char_code(\{x}))"
        IntegerType => "idris2i_1_mkIntegerFromDouble(\{x})"
        _ => "/* not a cast of doubles: Double to \{show to} */"
intOpC (Cast from DoubleType) [x] = case unboxedType from of
    Just _ => "IDRIS2I_1_DOUBLE((double)(\{x}))"
    Nothing => case from of
        CharType => "((double)idris2i_1_vp_to_Char(\{x}))"
        IntegerType => "IDRIS2I_1_DOUBLE(idris2i_1_integerToDouble(\{x}))"
        _ => "/* not a cast to doubles: \{show from} to Double */"
intOpC op@(Add DoubleType) args = doubleOpC op args
intOpC op@(Sub DoubleType) args = doubleOpC op args
intOpC op@(Mul DoubleType) args = doubleOpC op args
intOpC op@(Div DoubleType) args = doubleOpC op args
intOpC op@(Neg DoubleType) args = doubleOpC op args
intOpC op@(LT DoubleType) args = doubleOpC op args
intOpC op@(LTE DoubleType) args = doubleOpC op args
intOpC op@(EQ DoubleType) args = doubleOpC op args
intOpC op@(GTE DoubleType) args = doubleOpC op args
intOpC op@(GT DoubleType) args = doubleOpC op args
intOpC op@DoubleExp args = doubleOpC op args
intOpC op@DoubleLog args = doubleOpC op args
intOpC op@DoublePow args = doubleOpC op args
intOpC op@DoubleSin args = doubleOpC op args
intOpC op@DoubleCos args = doubleOpC op args
intOpC op@DoubleTan args = doubleOpC op args
intOpC op@DoubleASin args = doubleOpC op args
intOpC op@DoubleACos args = doubleOpC op args
intOpC op@DoubleATan args = doubleOpC op args
intOpC op@DoubleSqrt args = doubleOpC op args
intOpC op@DoubleFloor args = doubleOpC op args
intOpC op@DoubleCeiling args = doubleOpC op args
intOpC (Add ty) [x, y] = wrapping ty "+" x y
intOpC (Sub ty) [x, y] = wrapping ty "-" x y
intOpC (Mul ty) [x, y] = wrapping ty "*" x y
intOpC (Div ty) [x, y]
    = if isSigned ty then "idris2i_1_euclidDiv_\{runtimeName ty}(\{x}, \{y})"
                     else "idris2i_1_unsignedDiv_\{runtimeName ty}(\{x}, \{y})"
intOpC (Mod ty) [x, y]
    = if isSigned ty then "idris2i_1_euclidMod_\{runtimeName ty}(\{x}, \{y})"
                     else "idris2i_1_unsignedMod_\{runtimeName ty}(\{x}, \{y})"
intOpC (Neg ty) [x] = "((\{cIntType ty})(0u - (uint64_t)(\{x})))"
intOpC (ShiftL ty) [x, y] = "idris2i_1_shiftLeft_\{runtimeName ty}(\{x}, \{y})"
intOpC (ShiftR ty) [x, y] = "idris2i_1_shiftRight_\{runtimeName ty}(\{x}, \{y})"
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
        CharType => "idris2i_1_mkValidChar(\{x})"
        _ => if isSigned f then "idris2i_1_mkIntegerFromInt64(\{x})"
                           else "idris2i_1_mkIntegerFromUInt64(\{x})"
    (Nothing, Just t) => case from of
        CharType => "((\{cIntType t})idris2i_1_vp_to_Char(\{x}))"
        _ => "((\{cIntType t})idris2i_1_integerLow64(\{x}))"
    _ => "/* not a cast of fixed width integers: \{show from} to \{show to} */"
intOpC op _ = "/* not an operation on fixed width integers: \{show op} */"

||| The unboxed type of a literal, if it is a fixed width integer or a
||| `Double`.
export
constType : Constant -> Maybe PrimType
constType (Db _) = Just DoubleType
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

||| A C literal for a Double.  `show` gives the shortest digits that read back
||| as the same number, but in the notation of Scheme: drop the precision of a
||| subnormal number (`5e-324|1`) and spell out NaN and the infinities.
export
cDouble : Double -> String
cDouble x
    = if x /= x then "NAN"
      else if x == 1.0 / 0.0 then "INFINITY"
      else if x == -1.0 / 0.0 then "(-INFINITY)"
      else case takeWhile (/= '|') (unpack (show x)) of
             str@('-' :: _) => "(" ++ pack str ++ ")"
             str => pack str

||| The C constant of a fixed width integer or `Double` literal (C does not
||| allow `-9223372036854775808`).
export
cIntLiteral : Constant -> String
cIntLiteral (Db x) = cDouble x
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
  | ||| as the result of the function (a value, unless its worker gives a C
    ||| integer, see `rawResultOK`)
    Returned
  | ||| as it is: it must be a value
    Raw
  | ||| as the new value of a parameter (by its position), in a call of the
    ||| function to itself (`selfTailCall`)
    SelfArg Nat
  | ||| as the value of the `let` of the variable (in tail position in it,
    ||| in a branch of a `case`, say): a C integer if the variable is one
    Into Int

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
  ||| The C name of a function, by which the others know it (computed once
  ||| per call: it is not cheap)
  key : Name -> String
  ||| Are there workers?  (If not, the C names of the calls need not be made
  ||| to look for them.)
  anyWorkers : Bool
  ||| Is this call in tail position one of the function to itself, which
  ||| jumps back to its start (see `makeTailCall`)?
  isSelf : String -> List AVar -> Bool
  ||| Is it a call of a foreign function, which takes the variables as they
  ||| are (see `foreignCall`)?
  isForeign : String -> List AVar -> Bool
  ||| The types of the parameters that a function called with this number of
  ||| arguments takes as C integers, in order, when it has a worker (see
  ||| `Worker` in Compiler.RefC.RefC).
  rawArgs : String -> Nat -> Maybe (List (Maybe PrimType))
  ||| The type of the C integer that the worker of a function called with
  ||| this number of arguments gives, if it gives one.
  rawResult : String -> Nat -> Maybe PrimType
  ||| Does the function called with this number of arguments always give a
  ||| value, never a pending tail call (see `returnsValue` in RefC)?
  isValueFn : String -> Nat -> Bool
  ||| May variables be C doubles?  (`--directive refc-no-unbox-double` says
  ||| no: then only the integers are unboxed, as before.)
  doubles : Bool
  ||| The types of the parameters that a foreign function called with this
  ||| number of arguments takes as C numbers, and of its result if it gives
  ||| one, when it has a variant that does (see `foreignWorker` in RefC):
  ||| its other parameters take the values as they are.
  foreignRaw : String -> Nat -> Maybe (List (Maybe PrimType), Maybe PrimType)
  ||| Are there such foreign functions?
  anyForeignRaw : Bool
  ||| The types of the C numbers in which the fields of a constructor are
  ||| stored raw, field by field, if it has raw fields (see `RawLayout` in
  ||| Compiler.RefC.RefC): such a field is built from a C number, and read
  ||| as one.
  rawFields : Name -> Maybe (List (Maybe PrimType))
  ||| Are there such constructors?
  anyRawFields : Bool
  ||| Is a variable that a branch gives as the value of a `let` a C number
  ||| when the `let`'s variable is one (`Into`)?  Only for the programs that
  ||| use flat arrays, whose accesses make such `let`s (see
  ||| Compiler.RefC.FlatOpt): the others are compiled as before.
  into : Bool

||| Is a variable of this type allowed to be unboxed?
export
allowed : Calls -> PrimType -> Bool
allowed c DoubleType = c.doubles
allowed c _ = True

||| The calls of a function that knows no worker of any function.
export
noWorkers : (key : Name -> String) -> (isSelf : String -> List AVar -> Bool) ->
            (isForeign : String -> List AVar -> Bool) -> Calls
noWorkers k s f = MkCalls k False s f (\_, _ => Nothing) (\_, _ => Nothing) (\_, _ => False) True
                          (\_, _ => Nothing) False (const Nothing) False False

-- The uses of the arguments of a call: an argument of a parameter that the
-- worker of the function takes as a C integer is used as an integer of that
-- type.
argUses : Calls -> String -> List AVar -> Uses -> Uses
argUses c cn args us
    = case c.rawArgs cn (length args) of
           Just ts => foldl (\us', (a, t) => addUse (maybe Boxed Numeric t) a us') us
                            (zip args ts)
           Nothing => addUses Boxed args us

usesInto : Calls -> (tail : Bool) -> (into : Maybe Int) -> ANF -> Uses -> Uses
usesInto c t i (AV _ v) us = addUse (maybe (if t then Returned else Boxed) Into i) v us
usesInto c t i (AAppName _ _ n args) us
    = let cn = c.key n in
      if c.isForeign cn args
         then case c.foreignRaw cn (length args) of
                   Just (ts, _) => foldl (\us', (a, t) => addUse (maybe Raw Numeric t) a us') us
                                         (zip args ts)
                   Nothing => addUses Raw args us
      else if t && c.isSelf cn args
         then foldl (\us', (k, a) => addUse (SelfArg k) a us') us
                    (zip [0 .. length args] args)
         else argUses c cn args us
usesInto c t i (AUnderApp _ _ _ args) us = addUses Boxed args us
usesInto c t i (AApp _ _ f a) us = addUse Boxed f (addUse Boxed a us)
usesInto c t i (ALet _ x val body) us = usesInto c t i body (usesInto c False (if c.into then Just x else Nothing) val us)
-- (a raw field of a constructor is stored from a C number)
usesInto c t i (ACon _ n _ _ args) us
    = case c.rawFields n of
           Just ts => foldl (\us', (a, t) => addUse (maybe Boxed Numeric t) a us') us
                            (zip args ts)
           Nothing => addUses Boxed args us
usesInto c t i (AOp _ _ op args) us
    = addUses (maybe Raw Numeric (operandType op)) (toList args) us
-- (the arrays of slots with a layout take the layout and the index as C
-- numbers, see prim__slotGet in RefC)
usesInto c t i (AExtPrim _ _ p args) us
    = case (p, args) of
           (NS _ (UN (Basic "prim__newSlots")), [_, l, n, v, w]) =>
             addUse (Numeric Bits64Type) l (addUse (Numeric IntType) n (addUses Raw [v, w] us))
           (NS _ (UN (Basic "prim__slotGet")), [_, l, arr, i, w]) =>
             addUse (Numeric Bits64Type) l (addUse (Numeric IntType) i (addUses Raw [arr, w] us))
           (NS _ (UN (Basic "prim__slotSet")), [_, l, arr, i, v, w]) =>
             addUse (Numeric Bits64Type) l (addUse (Numeric IntType) i (addUses Raw [arr, v, w] us))
           _ => case (flatPrimName p, args) of
             -- (the accesses to the elements of flat arrays, see
             -- Compiler.RefC.FlatOpt: the layout, the index and the fields
             -- written are C numbers)
             (Just pn, l :: arr :: i :: rest) =>
               let us' = addUse (Numeric Bits64Type) l (addUse (Numeric IntType) i (addUse Raw arr us)) in
                   if isPrefixOf "slotStoreElem" pn then addUses Raw rest us'
                   else if isPrefixOf "slotStore" pn
                     then foldl (\u, (c, f) => addUse (Numeric (letterType c)) f u) us'
                                (zip (unpack (substr 9 (length pn) pn)) rest)
                   -- (a read takes the snapshot of the element as it is)
                   else addUses Raw rest us'
             _ => addUses Raw args us
usesInto c t i (AConCase _ sc alts def) us
    = let us = foldl (\us', (MkAConAlt _ _ _ _ b) => usesInto c t i b us') us alts
          us = maybe us (\d => usesInto c t i d us) def in
          addUse Raw sc us
usesInto c t i (AConstCase _ sc alts def) us
    = let us = foldl (\us', (MkAConstAlt _ b) => usesInto c t i b us') us alts
          us = maybe us (\d => usesInto c t i d us) def in
          case alts of
               [] => us -- (only a default: the scrutinee is not looked at)
               _ => addUse (maybe Raw Numeric (altsType alts)) sc us
usesInto _ _ _ _ us = us

usesIn : Calls -> (tail : Bool) -> ANF -> Uses -> Uses
usesIn c t = usesInto c t Nothing

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

||| Does the expression have an operation on C integers, or a call of a
||| worker that takes or gives one?
export
hasIntWork : Calls -> ANF -> Bool
hasIntWork c (AOp _ _ op _) = isJust (operandType op) || isJust (resultType op)
hasIntWork c (AAppName _ _ n args)
    = (c.anyWorkers || c.anyForeignRaw) &&
      (let k = length args
           cn = c.key n in
           isJust (c.rawResult cn k) || maybe False (any isJust) (c.rawArgs cn k)
           || isJust (c.foreignRaw cn k))
hasIntWork c (ALet _ _ val body) = hasIntWork c val || hasIntWork c body
-- (the arrays of slots take their layouts and indices as C numbers)
hasIntWork c (AExtPrim _ _ n@(NS _ (UN (Basic p))) _)
    = p == "prim__newSlots" || p == "prim__slotGet" || p == "prim__slotSet"
      || isJust (flatPrimName n)
-- (a constructor with raw fields is built from C numbers, and they are read
-- as C numbers)
hasIntWork c (ACon _ n _ _ _) = c.anyRawFields && isJust (c.rawFields n)
hasIntWork c (AConCase _ _ alts def)
    = any (\(MkAConAlt n _ _ _ b) => (c.anyRawFields && isJust (c.rawFields n)) || hasIntWork c b) alts
      || any (hasIntWork c) def
hasIntWork c (AConstCase _ _ alts def)
    = any (\(MkAConstAlt _ b) => hasIntWork c b) alts || any (hasIntWork c) def
hasIntWork _ _ = False

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

||| The variables bound to the raw fields of a constructor by the alternatives
||| of the `case`s (see `rawFields`), with their types.
rawBinders : Calls -> ANF -> SortedMap Int PrimType -> SortedMap Int PrimType
rawBinders c (ALet _ _ val body) bs = rawBinders c body (rawBinders c val bs)
rawBinders c (AConCase _ _ alts def) bs
    = let bs = foldl (\bs', (MkAConAlt n _ _ as b) =>
                        let bs'' = case c.rawFields n of
                                     Just ts => foldl (\m, (a, t) => maybe m (\t' => insert a t' m) t)
                                                      bs' (zip as ts)
                                     Nothing => bs' in
                            rawBinders c b bs'') bs alts in
          maybe bs (\d => rawBinders c d bs) def
rawBinders c (AConstCase _ _ alts def) bs
    = let bs = foldl (\bs', (MkAConstAlt _ b) => rawBinders c b bs') bs alts in
          maybe bs (\d => rawBinders c d bs) def
rawBinders _ _ bs = bs

||| The type of the C integer that an expression can be compiled to (see
||| `cIntFromANF` in RefC), given the variables that are C integers, if it
||| can be.
export
valueType : Calls -> SortedMap Int PrimType -> ANF -> Maybe PrimType
valueType c u e = case go e of
                     Just (Just t) => Just t
                     _ => Nothing
  where
    -- `Just Nothing`: any type (a crash)
    go : ANF -> Maybe (Maybe PrimType)
    -- (`%op crash`: the missing case of the `mod` or `div` of an `Int` by
    -- zero, say; `cIntFromANF` unboxes what it gives, as it never returns)
    go (AOp _ _ Crash _) = Just Nothing
    go (AOp _ _ op _) = map Just (resultType op)
    -- (the reads of the elements of flat arrays, see Compiler.RefC.FlatOpt)
    go (AExtPrim _ _ p _)
        = case flatPrimName p of
            Just "slotPresent" => Just (Just IntType)
            Just pn => if isPrefixOf "slotField" pn
                          then map (Just . letterType) (head' (unpack (substr 9 (length pn) pn)))
                          else Nothing
            Nothing => Nothing
    go (APrimVal _ c) = map Just (constType c)
    go (AV _ (ALocal v)) = map Just (lookup v u)
    -- (a call, not in tail position, of a worker that gives a C integer)
    go (AAppName _ _ n args)
        = let cn = c.key n in
              if c.isForeign cn args then map Just (c.foreignRaw cn (length args) >>= snd)
                 else map Just (c.rawResult cn (length args))
    go (ALet _ _ _ body) = go body
    go (AConstCase _ _ alts def)
        = do ts <- traverse (\(MkAConstAlt _ b) => go b) alts
             d <- traverse go def
             let known = catMaybes (maybe ts (:: ts) d)
             case known of
                  [] => Just Nothing
                  (t :: rest) => if all (== t) rest then Just (Just t) else Nothing
    -- (a `case` on constructors whose branches give C integers, the
    -- projection of a raw field, say)
    go (AConCase _ _ alts def)
        = do ts <- traverse (\(MkAConAlt _ _ _ _ b) => go b) alts
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
||| tells whether the function calls itself in tail position, `worker`
||| whether it has a worker (see `Worker` in Compiler.RefC.RefC): then a
||| parameter that it returns can be a C integer, as its callers pass one (and
||| no value is made when the result of the worker is a C integer).
export
unboxedVars : Calls -> (loops : Bool) -> (worker : Bool) -> (params : List Int) ->
              (intParams : SortedMap Int PrimType) -> ANF -> SortedMap Int PrimType
unboxedVars c loops worker params ips body
    -- (`us` and `lets` are computed once: as definitions of the `where`
    -- block, they would be computed at each use.)
    = let us = usesIn c True body empty
          lets = letValues body empty
          fields = if c.anyRawFields then rawBinders c body empty else empty
          ps = mapMaybe (\p => lookup p ips >>= \t =>
                                  if allowed c t then Just (p, t) else Nothing) params
          fs = filter (\(_, t) => allowed c t) (SortedMap.toList fields) in
          if null (keys lets) && null ps && null fs
             then empty
             else keep us lets fields (candidates (SortedMap.toList lets) (mergeLeft (fromList ps) (fromList fs)))
  where
    -- The parameters, and the `let`s whose values can be C integers if the
    -- variables found so far are (a `let` may be a copy of another one).
    candidates : List (Int, ANF) -> SortedMap Int PrimType -> SortedMap Int PrimType
    candidates ls u
        = let new = mapMaybe (\(v, val) => if isJust (lookup v u) then Nothing
                                             else valueType c u val >>= \t =>
                                                    if allowed c t then Just (v, t) else Nothing) ls in
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
    numeric u t (Into x) = lookup x u == Just t
    numeric u t _ = False

    -- a use as a value, which needs one to be made
    boxed : SortedMap Int PrimType -> PrimType -> Use -> Bool
    boxed u t Boxed = True
    boxed u t Returned = True
    boxed u t (SelfArg k) = not (numeric u t (SelfArg k))
    boxed u t (Into x) = lookup x u /= Just t
    boxed u t _ = False

    -- a use that needs the value as it is (or as an integer of another type)
    raw : PrimType -> Use -> Bool
    raw t Raw = True
    raw t (Numeric t') = t /= t'
    raw t _ = False

    -- A Double literal is a static value (see `StaticVal` in RefC), which a
    -- C double would have to box again where a value is needed.
    staticLiteral : ANF -> Bool
    staticLiteral (APrimVal _ (Db _)) = True
    staticLiteral _ = False

    returned : Use -> Bool
    returned Returned = True
    returned _ = False

    isNumeric : PrimType -> Use -> Bool
    isNumeric t (Numeric t') = t == t'
    isNumeric _ _ = False

    ok : Uses -> SortedMap Int ANF -> SortedMap Int PrimType -> SortedMap Int PrimType -> (Int, PrimType) -> Bool
    ok us lets fields u (v, t)
        = let vs = fromMaybe [] (lookup v us) in
          not (any (raw t) vs) &&
          -- A raw field is a C number as it is read: unboxing it costs
          -- nothing, and a use as a value makes one, as reading it as a
          -- value would.  So it is one unless it has two uses as a value.
          if isJust (lookup v fields) then length (filter (boxed u t) vs) <= 1 else
          case lookup v lets of
               Just val => valueType c u val == Just t
                           && any (numeric u t) vs
                           && length (filter (boxed u t) vs) <= (if staticLiteral val then 0 else 1)
               -- a parameter: passing it on to itself is not a reason (it
               -- would only be unboxed and boxed again)
               Nothing => any (isNumeric t) vs
                          && (loops || all (\x => not (boxed u t x) || (worker && returned x)) vs)

    -- The variables are removed until those left are all fine with each
    -- other (a parameter and the `let` giving its next value, for example).
    keep : Uses -> SortedMap Int ANF -> SortedMap Int PrimType -> SortedMap Int PrimType -> SortedMap Int PrimType
    keep us lets fields u
        = let vs = SortedMap.toList u
              vs' = filter (ok us lets fields u) vs in
              if length vs' == length vs
                 then u
                 else keep us lets fields (fromList vs')

||| Can the worker of a function whose result has the fixed width integer
||| type `t` give the C integer, rather than a value, given the variables `u`
||| that are C integers?  So it can when every expression in tail position
||| gives one: an operation, a literal, a variable that is a C integer of the
||| type, a crash, a call of the function to itself (which jumps back to its
||| start), or a call of a function that gives a C integer and never a
||| pending tail call (`isValueFn`), and one of them is not a crash or a jump.
||| A call of another function would not be a tail call any more; a call of a
||| function that gives a C integer is not one either, but such a function
||| makes no tail call itself (but those that jump), so the stack does not
||| grow with a chain of them.  A variable that is a value is not unboxed to
||| be returned: a caller that needs a value would make another one.
export
rawResultOK : Calls -> SortedMap Int PrimType -> PrimType -> ANF -> Bool
rawResultOK c u t e = go e == Just True
  where
    -- Just True: fine, and gives a C integer; Just False: fine (a crash or
    -- a jump); Nothing: not fine.
    both : Maybe Bool -> Maybe Bool -> Maybe Bool
    both (Just a) (Just b) = Just (a || b)
    both _ _ = Nothing

    go : ANF -> Maybe Bool
    go (AV _ (ALocal v)) = if lookup v u == Just t then Just True else Nothing
    go (APrimVal _ k) = if constType k == Just t then Just True else Nothing
    go (AOp _ _ Crash _) = Just False
    go (AOp _ _ op _) = if resultType op == Just t then Just True else Nothing
    go (ACrash _ _) = Just False
    go (ALet _ _ _ body) = go body
    go (AConCase _ _ alts def)
        = foldl (\acc, (MkAConAlt _ _ _ _ b) => both acc (go b))
                (maybe (Just False) go def) alts
    go (AConstCase _ _ alts def)
        = foldl (\acc, (MkAConstAlt _ b) => both acc (go b))
                (maybe (Just False) go def) alts
    go (AAppName _ _ n args)
        = let cn = c.key n in
          if c.isSelf cn args then Just False
          -- (a foreign function makes no tail call)
          else if c.isForeign cn args
             then if (c.foreignRaw cn (length args) >>= snd) == Just t then Just True else Nothing
          else if c.rawResult cn (length args) == Just t
                  && c.isValueFn cn (length args)
             then Just True
             else Nothing
    go _ = Nothing

||| The literal of the type `t` that the cast of the Integer `x` gives: the
||| Integer is wrapped around to the width of the type, as the casts of the
||| runtime do (`idris2i_1_cast_Integer_to_Bits8`, ...).  This is computed on
||| Integers, so it does not depend on the machine that runs the compiler.
export
castIntegerLiteral : PrimType -> Integer -> Maybe Constant
-- (a Double only when it is exact, as every backend converts it so: beyond
-- 2^53 the rounding would be that of the machine running the compiler)
castIntegerLiteral DoubleType x
    = if x >= -9007199254740992 && x <= 9007199254740992
         then Just (Db (cast x))
         else Nothing
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
||| it every time it is computed.  So are those to `Double`, when the Double
||| is exact (see `castIntegerLiteral`).  The `let`s of the Integers that are
||| then unused are removed.
export
foldIntegerCasts : ANF -> ANF
foldIntegerCasts e
    = let ints = integerLets e empty
          others = otherUses ints e empty in
          go others ints e
  where
    -- The `let`s of Integer literals (the variables of a definition are all
    -- different).
    integerLets : ANF -> SortedMap Int Integer -> SortedMap Int Integer
    integerLets (ALet _ v (APrimVal _ (BI x)) body) ls = integerLets body (insert v x ls)
    integerLets (ALet _ _ val body) ls = integerLets body (integerLets val ls)
    integerLets (AConCase _ _ alts def) ls
        = let ls = foldl (\ls', (MkAConAlt _ _ _ _ b) => integerLets b ls') ls alts in
              maybe ls (\d => integerLets d ls) def
    integerLets (AConstCase _ _ alts def) ls
        = let ls = foldl (\ls', (MkAConstAlt _ b) => integerLets b ls') ls alts in
              maybe ls (\d => integerLets d ls) def
    integerLets _ ls = ls

    -- The literal that a cast of the variable gives, if it is folded.
    folded : SortedMap Int Integer -> PrimType -> Int -> Maybe Constant
    folded ints t v = lookup v ints >>= castIntegerLiteral t

    vars : List AVar -> SortedSet Int -> SortedSet Int
    vars as s = foldl (\s', a => case a of
                                     ALocal i => insert i s'
                                     ANull => s') s as

    -- The variables with a use other than a cast that is folded.
    otherUses : SortedMap Int Integer -> ANF -> SortedSet Int -> SortedSet Int
    otherUses ints (AOp _ _ (Cast IntegerType t) [ALocal v]) s
        = if isJust (folded ints t v) then s else insert v s
    otherUses ints (AV _ v) s = vars [v] s
    otherUses ints (AAppName _ _ _ as) s = vars as s
    otherUses ints (AUnderApp _ _ _ as) s = vars as s
    otherUses ints (AApp _ _ f a) s = vars [f, a] s
    otherUses ints (ALet _ _ val body) s = otherUses ints body (otherUses ints val s)
    otherUses ints (ACon _ _ _ _ as) s = vars as s
    otherUses ints (AOp _ _ op as) s = vars (toList as) s
    otherUses ints (AExtPrim _ _ _ as) s = vars as s
    otherUses ints (AConCase _ sc alts def) s
        = let s = foldl (\s', (MkAConAlt _ _ _ _ b) => otherUses ints b s') (vars [sc] s) alts in
              maybe s (\d => otherUses ints d s) def
    otherUses ints (AConstCase _ sc alts def) s
        = let s = foldl (\s', (MkAConstAlt _ b) => otherUses ints b s') (vars [sc] s) alts in
              maybe s (\d => otherUses ints d s) def
    otherUses _ _ s = s

    go : SortedSet Int -> SortedMap Int Integer -> ANF -> ANF
    go others ls (ALet fc v val@(APrimVal _ (BI x)) body)
        = let body' = go others ls body in
              if contains v others then ALet fc v val body' else body'
    go others ls (ALet fc v val body) = ALet fc v (go others ls val) (go others ls body)
    go others ls e@(AOp fc _ (Cast IntegerType t) [ALocal v])
        = maybe e (APrimVal fc) (folded ls t v)
    go others ls (AConCase fc sc alts def)
        = AConCase fc sc (map (\(MkAConAlt n ci t as b) => MkAConAlt n ci t as (go others ls b)) alts)
                   (map (go others ls) def)
    go others ls (AConstCase fc sc alts def)
        = AConstCase fc sc (map (\(MkAConstAlt c b) => MkAConstAlt c (go others ls b)) alts)
                     (map (go others ls) def)
    go _ _ e = e
