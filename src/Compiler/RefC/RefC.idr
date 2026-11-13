module Compiler.RefC.RefC

import Compiler.RefC.CC
import Compiler.RefC.Unbox

import Compiler.Common
import Compiler.CompileExpr
import Compiler.ANF
import Compiler.Generated

import Core.Directory

import Idris.Syntax

import Libraries.Data.DList
import Libraries.Data.NatSet
import Data.SortedSet
import Data.SortedMap
import Data.Bits
import Data.Vect

import System
import System.File

import Protocol.Hex
import Libraries.Utils.Path

%default covering


showcCleanStringChar : Char -> String -> String
showcCleanStringChar ' ' = ("_" ++)
showcCleanStringChar '!' = ("_bang" ++)
showcCleanStringChar '"' = ("_quotation" ++)
showcCleanStringChar '#' = ("_number" ++)
showcCleanStringChar '$' = ("_dollar" ++)
showcCleanStringChar '%' = ("_percent" ++)
showcCleanStringChar '&' = ("_and" ++)
showcCleanStringChar '\'' = ("_tick" ++)
showcCleanStringChar '(' = ("_parenOpen" ++)
showcCleanStringChar ')' = ("_parenClose" ++)
showcCleanStringChar '*' = ("_star" ++)
showcCleanStringChar '+' = ("_plus" ++)
showcCleanStringChar ',' = ("_comma" ++)
showcCleanStringChar '-' = ("__" ++)
showcCleanStringChar '.' = ("_dot" ++)
showcCleanStringChar '/' = ("_slash" ++)
showcCleanStringChar ':' = ("_colon" ++)
showcCleanStringChar ';' = ("_semicolon" ++)
showcCleanStringChar '<' = ("_lt" ++)
showcCleanStringChar '=' = ("_eq" ++)
showcCleanStringChar '>' = ("_gt" ++)
showcCleanStringChar '?' = ("_question" ++)
showcCleanStringChar '@' = ("_at" ++)
showcCleanStringChar '[' = ("_bracketOpen" ++)
showcCleanStringChar '\\' = ("_backslash" ++)
showcCleanStringChar ']' = ("_bracketClose" ++)
showcCleanStringChar '^' = ("_hat" ++)
showcCleanStringChar '_' = ("_" ++)
showcCleanStringChar '`' = ("_backquote" ++)
showcCleanStringChar '{' = ("_braceOpen" ++)
showcCleanStringChar '|' = ("_or" ++)
showcCleanStringChar '}' = ("_braceClose" ++)
showcCleanStringChar '~' = ("_tilde" ++)
showcCleanStringChar c
   = if c < chr 32 || c > chr 126
        then (("u" ++ leftPad '0' 4 (asHex (cast c))) ++)
        else strCons c

showcCleanString : List Char -> String -> String
showcCleanString [] = id
showcCleanString (c ::cs) = (showcCleanStringChar c) . showcCleanString cs

cCleanString : String -> String
cCleanString cs = showcCleanString (unpack cs) ""

export
cUserName : UserName -> String
cUserName (Basic n) = cCleanString n
cUserName (Field n) = "rec__" ++ cCleanString n
cUserName Underscore = cCleanString "_"

export
cName : Name -> String
cName (NS ns n) = cCleanString (showNSWithSep "_" ns) ++ "_" ++ cName n
cName (UN n) = cUserName n
cName (MN n i) = cCleanString n ++ "_" ++ cCleanString (show i)
cName (PV n d) = "pat__" ++ cName n
cName (DN _ n) = cName n
cName (Nested i n) = "n__" ++ cCleanString (show i) ++ "_" ++ cName n
cName (CaseBlock x y) = "case__" ++ cCleanString (show x) ++ "_" ++ cCleanString (show y)
cName (WithBlock x y) = "with__" ++ cCleanString (show x) ++ "_" ++ cCleanString (show y)
cName (Resolved i) = "fn__" ++ cCleanString (show i)

-- A character is its code point; RefC stores it unboxed, in at least 32 bits.
escapeChar : Char -> String
escapeChar c = if (isAlphaNum c || isNL c) && c < chr 128
                  then show c
                  else show (ord c)

||| The bytes of the UTF-8 encoding of a character.
utf8Bytes : Char -> List Int
utf8Bytes c
    = let x = ord c in
      if x < 0x80 then [x]
      else if x < 0x800 then [0xC0 + shiftR x 6, cont x]
      else if x < 0x10000 then [0xE0 + shiftR x 12, cont (shiftR x 6), cont x]
      else [0xF0 + shiftR x 18, cont (shiftR x 12), cont (shiftR x 6), cont x]
  where
    cont : Int -> Int
    cont y = 0x80 + (y .&. 0x3F)

-- Strings are UTF-8 at runtime.  Characters outside printable ASCII are written
-- as the hexadecimal escapes of their bytes, which does not depend on the
-- execution character set of the C compiler.  An escape is followed by `""` so
-- that a hexadecimal digit after it is not read as part of it.
cStringQuoted : String -> String
cStringQuoted cs = strCons '"' (showCString (unpack cs) "\"")
where
    hexByte : Int -> String -> String
    hexByte b = (("\\x" ++ leftPad '0' 2 (asHex (cast b))) ++ "\"\"" ++)

    showCChar : Char -> String -> String
    showCChar '\\' = ("\\\\" ++)
    showCChar c
       = if c < chr 32 || c >= chr 127
            then foldr (\b, k => hexByte b . k) id (utf8Bytes c)
            else strCons c

    showCString : List Char -> String -> String
    showCString [] = id
    showCString ('"'::cs) = ("\\\"" ++) . showCString cs
    showCString (c ::cs) = (showCChar c) . showCString cs

||| A C literal for a Double.  `show` gives the shortest digits that read back
||| as the same number, but in the notation of Scheme: drop the precision of a
||| subnormal number (`5e-324|1`) and spell out NaN and the infinities.
cDouble : Double -> String
cDouble x
    = if x /= x then "NAN"
      else if x == 1.0 / 0.0 then "INFINITY"
      else if x == -1.0 / 0.0 then "(-INFINITY)"
      else case takeWhile (/= '|') (unpack (show x)) of
             str@('-' :: _) => "(" ++ pack str ++ ")"
             str => pack str

-- deals with C not allowing `-9223372036854775808` as a literal
showIntMin : Int -> String
showIntMin x = if x == -9223372036854775808
    then "INT64_MIN"
    else "INT64_C("++ show x ++")"

showInt64Min : Int64 -> String
showInt64Min x = if x == -9223372036854775808
    then "INT64_MIN"
    else "INT64_C("++ show x ++")"

cPrimType : PrimType -> String
cPrimType IntType = "Int64"
cPrimType Int8Type = "Int8"
cPrimType Int16Type = "Int16"
cPrimType Int32Type = "Int32"
cPrimType Int64Type = "Int64"
cPrimType IntegerType = "Integer"
cPrimType Bits8Type = "Bits8"
cPrimType Bits16Type = "Bits16"
cPrimType Bits32Type = "Bits32"
cPrimType Bits64Type = "Bits64"
cPrimType StringType = "string"
cPrimType CharType = "Char"
cPrimType DoubleType = "Double"
cPrimType WorldType = "void"

||| Generate scheme for a primitive function.
cOp : {0 arity : Nat} -> PrimFn arity -> Vect arity String -> String
cOp (Neg ty)      [x]       = "idris2_negate_"  ++  cPrimType ty ++ "(" ++ x ++ ")"
cOp StrLength     [x]       = "stringLength(" ++ x ++ ")"
cOp StrHead       [x]       = "head(" ++ x ++ ")"
cOp StrTail       [x]       = "tail(" ++ x ++ ")"
cOp StrReverse    [x]       = "reverse(" ++ x ++ ")"
cOp (Cast i o)    [x]       = "idris2_cast_" ++ (cPrimType i) ++ "_to_" ++ (cPrimType o) ++ "(" ++ x ++ ")"
cOp DoubleExp     [x]       = "idris2_mkDouble(exp(idris2_vp_to_Double(" ++ x ++ ")))"
cOp DoubleLog     [x]       = "idris2_mkDouble(log(idris2_vp_to_Double(" ++ x ++ ")))"
cOp DoublePow     [x, y]    = "idris2_mkDouble(pow(idris2_vp_to_Double(" ++ x ++ "), idris2_vp_to_Double(" ++ y ++ ")))"
cOp DoubleSin     [x]       = "idris2_mkDouble(sin(idris2_vp_to_Double(" ++ x ++ ")))"
cOp DoubleCos     [x]       = "idris2_mkDouble(cos(idris2_vp_to_Double(" ++ x ++ ")))"
cOp DoubleTan     [x]       = "idris2_mkDouble(tan(idris2_vp_to_Double(" ++ x ++ ")))"
cOp DoubleASin    [x]       = "idris2_mkDouble(asin(idris2_vp_to_Double(" ++ x ++ ")))"
cOp DoubleACos    [x]       = "idris2_mkDouble(acos(idris2_vp_to_Double(" ++ x ++ ")))"
cOp DoubleATan    [x]       = "idris2_mkDouble(atan(idris2_vp_to_Double(" ++ x ++ ")))"
cOp DoubleSqrt    [x]       = "idris2_mkDouble(sqrt(idris2_vp_to_Double(" ++ x ++ ")))"
cOp DoubleFloor   [x]       = "idris2_mkDouble(floor(idris2_vp_to_Double(" ++ x ++ ")))"
cOp DoubleCeiling [x]       = "idris2_mkDouble(ceil(idris2_vp_to_Double(" ++ x ++ ")))"
cOp (Add ty)      [x, y]    = "idris2_add_" ++ cPrimType ty ++ "(" ++ x ++ ", " ++ y ++ ")"
cOp (Sub ty)      [x, y]    = "idris2_sub_" ++ cPrimType ty ++ "(" ++ x ++ ", " ++ y ++ ")"
cOp (Mul ty)      [x, y]    = "idris2_mul_" ++ cPrimType ty ++ "(" ++ x ++ ", " ++ y ++ ")"
cOp (Div ty)      [x, y]    = "idris2_div_" ++ cPrimType ty ++ "(" ++ x ++ ", " ++ y ++ ")"
cOp (Mod ty)      [x, y]    = "idris2_mod_" ++ cPrimType ty ++ "(" ++ x ++ ", " ++ y ++ ")"
cOp (ShiftL ty)   [x, y]    = "idris2_shiftl_" ++ cPrimType ty ++ "(" ++ x ++ ", " ++ y ++ ")"
cOp (ShiftR ty)   [x, y]    = "idris2_shiftr_" ++ cPrimType ty ++ "(" ++ x ++ ", " ++ y ++ ")"
cOp (BAnd ty)     [x, y]    = "idris2_and_" ++ cPrimType ty ++ "(" ++ x ++ ", " ++ y ++ ")"
cOp (BOr ty)      [x, y]    = "idris2_or_" ++ cPrimType ty ++ "(" ++ x ++ ", " ++ y ++ ")"
cOp (BXOr ty)     [x, y]    = "idris2_xor_" ++ cPrimType ty ++ "(" ++ x ++ ", " ++ y ++ ")"
cOp (LT ty)       [x, y]    = "idris2_lt_" ++ cPrimType ty ++ "(" ++ x ++ ", " ++ y ++ ")"
cOp (GT ty)       [x, y]    = "idris2_gt_" ++ cPrimType ty ++ "(" ++ x ++ ", " ++ y ++ ")"
cOp (EQ ty)       [x, y]    = "idris2_eq_" ++ cPrimType ty ++ "(" ++ x ++ ", " ++ y ++ ")"
cOp (LTE ty)      [x, y]    = "idris2_lte_" ++ cPrimType ty ++ "(" ++ x ++ ", " ++ y ++ ")"
cOp (GTE ty)      [x, y]    = "idris2_gte_" ++ cPrimType ty ++ "(" ++ x ++ ", " ++ y ++ ")"
cOp StrIndex      [x, i]    = "strIndex(" ++ x ++ ", " ++ i ++ ")"
cOp StrCons       [x, y]    = "strCons(" ++ x ++ ", " ++ y ++ ")"
cOp StrAppend     [x, y]    = "strAppend(" ++ x ++ ", " ++ y ++ ")"
cOp StrSubstr     [x, y, z] = "strSubstr(" ++ x ++ ", " ++ y  ++ ", " ++ z ++ ")"
cOp BelieveMe     [_, _, x] = "idris2_newReference(" ++ x ++ ")"
cOp Crash         [_, msg]  = "idris2_crash(" ++ msg ++ ");"
cOp fn args = show fn ++ "(" ++ (showSep ", " $ toList args) ++ ")"

varName : AVar -> String
varName (ALocal i) = "var_" ++ (show i)
varName (ANull)    = "NULL"

data ArgCounter : Type where
data EnvTracker : Type where
data Foreigns : Type where
data FunctionDefinitions : Type where
data IndentLevel : Type where
data HeaderFiles : Type where
data ConstDef
  = CDI64 String
  | CDB64 String
  | CDDb  String
  | CDStr String
  | CDBI  String -- created on first use (see idris2_integerConstant)

constantName : ConstDef -> String
constantName = \case
  CDI64 x => go "Int64" x
  CDB64 x => go "Bits64" x
  CDDb x  => go "Double" x
  CDStr x => go "String" x
  CDBI x  => go "Integer" x
  where go : String -> String -> String
        go x y = "idris2_constant_\{x}_\{y}"

ReuseMap = SortedMap Name String
Owned = SortedSet AVar

||| Environment for precise reference counting.
||| If variable borrowed (that is, it is not in the owned set) when used, call a function idris2_newReference.
||| If variable owned, then use it directly.
||| Reuse Map contains the name of the reusable constructor and variable
record Env where
  constructor MkEnv
  owned : Owned
  reuseMap : ReuseMap
  ||| The C name and the parameters of the function being compiled, when its
  ||| calls to itself in tail position can jump back to its start (see
  ||| `selfTailCall`).
  self : Maybe (String, List Int)
  ||| The number of parameters of the function being compiled (see
  ||| `makeTailCall`).
  selfArity : Nat
  ||| The arities of the foreign functions, by C name (see `foreignCall`).
  foreigns : SortedMap String Nat
  ||| The variables that are C integers, `int_N` instead of `var_N` (see
  ||| Compiler.RefC.Unbox).  They are never owned: they are not values.
  unboxed : SortedSet Int

------------------------------------------------------------------------
-- Output generation: using a difference list for efficient append

data OutfileText : Type where

Output : Type
Output = DList String

------------------------------------------------------------------------

getNextCounter : {auto a : Ref ArgCounter Nat} -> Core String
getNextCounter = do
    c <- get ArgCounter
    put ArgCounter (S c)
    pure $ show c

getNewVarThatWillNotBeFreedAtEndOfBlock : {auto a : Ref ArgCounter Nat} -> Core String
getNewVarThatWillNotBeFreedAtEndOfBlock = pure $ "tmp_" ++ !(getNextCounter)


maxLineLengthForComment : Nat
maxLineLengthForComment = 60

lJust : (line:String) -> (fillPos:Nat) -> (filler:Char) -> String
lJust line fillPos filler =
    let n = length line in
    case isLTE n fillPos of
        (Yes prf) =>
            let missing = minus fillPos n
                fillBlock = pack (replicate missing filler)
            in
            line ++ fillBlock
        (No _) => line

increaseIndentation : {auto il : Ref IndentLevel Nat} -> Core ()
increaseIndentation = update IndentLevel S

decreaseIndentation : {auto il : Ref IndentLevel Nat} -> Core ()
decreaseIndentation = update IndentLevel pred

indentation : {auto il : Ref IndentLevel Nat} -> Core String
indentation = do
    iLevel <- get IndentLevel
    pure $ pack $ replicate (4 * iLevel) ' '

emit
  : {auto oft : Ref OutfileText Output} ->
    {auto il : Ref IndentLevel Nat} ->
    FC -> String -> Core ()
emit EmptyFC line = do
    indent <- indentation
    update OutfileText (flip snoc (indent ++ line))
emit fc line = do
    let comment = "// " ++ show fc
    indent <- indentation
    let indentedLine = indent ++ line
    update OutfileText $ case isLTE (length indentedLine) maxLineLengthForComment of
        (Yes _) => flip snoc (lJust indentedLine maxLineLengthForComment ' ' ++ " " ++ comment)
        (No _)  => flip appendR [indentedLine, (lJust ""   maxLineLengthForComment ' ' ++ " " ++ comment)]

applyFunctionToVars : {auto oft : Ref OutfileText Output}
                    -> {auto il : Ref IndentLevel Nat}
                    -> String
                    -> List String
                    -> Core ()
applyFunctionToVars fun vars = traverse_ (\v => emit EmptyFC $ fun ++ "(" ++ v ++ ");" ) vars

removeVars : {auto oft : Ref OutfileText Output}
           -> {auto il : Ref IndentLevel Nat}
           -> List String
           -> Core ()
removeVars = applyFunctionToVars "idris2_removeReference"

dupVars : {auto oft : Ref OutfileText Output}
           -> {auto il : Ref IndentLevel Nat}
           -> List String
           -> Core ()
dupVars = applyFunctionToVars "idris2_newReference"


removeReuseConstructors : {auto oft : Ref OutfileText Output}
                        -> {auto il : Ref IndentLevel Nat}
                        -> List String
                        -> Core ()
removeReuseConstructors = applyFunctionToVars "idris2_removeReuseConstructor"

||| The C integer that the variable `N` is when it is unboxed (see
||| Compiler.RefC.Unbox).
intVarName : Int -> String
intVarName i = "int_" ++ show i

isUnboxedIn : SortedSet Int -> AVar -> Bool
isUnboxedIn u (ALocal i) = contains i u
isUnboxedIn _ ANull = False

||| A new value (that the caller owns) made from a variable that is a C
||| integer.
boxInt : AVar -> String
boxInt (ALocal i) = "idris2_mkInt64(\{intVarName i})"
boxInt ANull = "NULL"

||| The C integer of a variable of type `Int`, unboxed or not.  (The variable
||| is borrowed.)
intOperand : Env -> AVar -> String
intOperand env v@(ALocal i)
    = if contains i env.unboxed then intVarName i
         else "idris2_vp_to_Int64(\{varName v})"
intOperand _ ANull = "0"

avarToC : Env -> AVar -> String
avarToC env var =
    if isUnboxedIn env.unboxed var then boxInt var
    else if contains var env.owned then varName var
        -- case when the variable is borrowed
    else "idris2_newReference(" ++ varName var ++ ")"

avarsToC : SortedSet Int -> Owned -> List AVar -> List String
avarsToC _ _ [] = []
avarsToC u owned (v::vars) =
  let v' = varName v in
      if isUnboxedIn u v
          then boxInt v :: avarsToC u owned vars
      else if contains v owned
          then v'::avarsToC u (delete v owned) vars
          else "idris2_newReference(\{v'})"::avarsToC u owned vars -- when v is borrowed

moveFromOwnedToBorrowed : Env -> SortedSet AVar -> Env
moveFromOwnedToBorrowed env vars = { owned $= (`difference` vars) } env

fillArgs : {auto oft : Ref OutfileText Output}
         -> {auto il : Ref IndentLevel Nat}
         -> Env
         -> String
         -> List AVar
         -> Nat
         -> Core ()
fillArgs _ _ [] _ = pure ()
fillArgs env arglist (v :: vars) k = do
    let ownedVars = if contains v env.owned then singleton v else empty
    emit EmptyFC $ "\{arglist}[\{show k}] = \{avarToC env v};"
    fillArgs (moveFromOwnedToBorrowed env ownedVars) arglist vars (S k)

makeClosure : {auto a : Ref ArgCounter Nat}
            -> {auto oft : Ref OutfileText Output}
            -> {auto il : Ref IndentLevel Nat}
            -> {auto e : Ref EnvTracker Env}
            -> FC
            -> Name
            -> List AVar
            -> Nat
            -> Core String
makeClosure fc n args missing = do
    let closure = "closure_\{!(getNextCounter)}"
    let nargs = length args
    emit fc "Idris2_Value *\{closure} = (Idris2_Value *)idris2_mkClosure((Idris2_Value *(*)())\{cName n}, \{show $ nargs + missing}, \{show nargs});"
    fillArgs !(get EnvTracker) "((Idris2_Closure*)\{closure})->args" args 0
    pure closure

||| A call in tail position: store it in the pending tail call, which the
||| trampoline of the caller makes, instead of allocating a closure for it (see
||| runtime.h).
makeTailCall : {auto a : Ref ArgCounter Nat}
            -> {auto oft : Ref OutfileText Output}
            -> {auto il : Ref IndentLevel Nat}
            -> {auto e : Ref EnvTracker Env}
            -> FC
            -> Name
            -> List AVar
            -> Core String
makeTailCall fc n args = do
    env <- get EnvTracker
    case env.self of
      Just (self, params) =>
        if self == cName n && length params == length args
           then selfTailCall env params
           else otherCall env
      Nothing => otherCall env
  where
    pendingCallVar : Core String
    pendingCallVar = do
      let pc = "pending_\{!(getNextCounter)}"
      emit fc "Idris2_PendingTailCall *\{pc} = &idris2_pendingTailCall;"
      pure pc

    -- (the worker, which holds the pending call, is found once: nothing in
    -- between can switch threads)
    pendingCall : Core String
    pendingCall = do
      pc <- pendingCallVar
      emit fc "\{pc}->f = (void *)\{cName n};"
      emit fc "\{pc}->arity = \{show $ length args};"
      fillArgs !(get EnvTracker) "\{pc}->args" args 0
      pure "IDRIS2_TAILCALL"

    -- With GCC 15 or later, a call in tail position is a jump (musttail),
    -- which does not need the trampoline.  It is only possible when the
    -- callee does not take more arguments than the caller (they would not fit
    -- in the space of the arguments of the caller on the stack, depending on
    -- the ABI).  Other compilers use a pending tail call.
    otherCall : Env -> Core String
    otherCall env =
      if length args <= env.selfArity
         then do
           let args' = avarsToC env.unboxed env.owned args
           emit fc "#ifdef IDRIS2_MUSTTAIL"
           emit fc "IDRIS2_MUSTTAIL return \{cName n}(\{concat $ intersperse ", " args'});"
           emit fc "#else"
           pc <- pendingCallVar
           emit fc "\{pc}->f = (void *)\{cName n};"
           emit fc "\{pc}->arity = \{show $ length args};"
           for_ (zip [0 .. length args] args') $ \(k, a) =>
             emit fc "\{pc}->args[\{show k}] = \{a};"
           emit fc "return IDRIS2_TAILCALL;"
           emit fc "#endif"
           pure "NULL /* unreachable */"
         else pendingCall

    -- A call of the function to itself: the arguments become the new values
    -- of the parameters, and the function starts again.  They are computed
    -- first, as they may refer to the parameters.  The parameters that are C
    -- integers get the integers of their arguments (see
    -- Compiler.RefC.Unbox): the arguments that we own, and that are not
    -- passed as values too, are released.
    selfTailCall : Env -> List Int -> Core String
    selfTailCall env params = do
      let pairs = zip params args
      let ints = filter (\(p, _) => contains p env.unboxed) pairs
      let values = filter (\(p, _) => not (contains p env.unboxed)) pairs
      let vals = avarsToC env.unboxed env.owned (map snd values)
      tmps <- traverse (\_ => getNewVarThatWillNotBeFreedAtEndOfBlock) vals
      for_ (zip tmps vals) $ \(t, v) => emit fc "Idris2_Value *\{t} = \{v};"
      itmps <- traverse (\(_, a) => do
                 t <- getNewVarThatWillNotBeFreedAtEndOfBlock
                 emit fc "int64_t \{t} = \{intOperand env a};"
                 pure t) ints
      let passed = SortedSet.fromList (map snd values)
      let released = filter (\v => contains v env.owned && not (contains v passed))
                            (nub (map snd ints))
      removeVars (map varName released)
      for_ (zip (map fst values) tmps) $ \(p, t) => emit fc "var_\{show p} = \{t};"
      for_ (zip (map fst ints) itmps) $ \(p, t) => emit fc "\{intVarName p} = \{t};"
      -- A loop may run for long: let the other threads of the worker run
      -- if the scheduler asks for it.
      emit fc "IDRIS2_SAFEPOINT();"
      emit fc "goto idris2_self_entry;"
      pure "NULL /* unreachable */"


||| Does the function with the C name `self` and `nargs` parameters call
||| itself in tail position in `anf` (see `selfTailCall`)?
hasSelfTailCall : String -> Nat -> ANF -> Bool
hasSelfTailCall self nargs = go
  where
    go : ANF -> Bool
    go (AAppName _ _ n args) = cName n == self && length args == nargs
    go (ALet _ _ _ body) = go body
    go (AConCase _ _ alts def)
        = any (\(MkAConAlt _ _ _ _ body) => go body) alts || maybe False go def
    go (AConstCase _ _ alts def)
        = any (\(MkAConstAlt _ body) => go body) alts || maybe False go def
    go _ = False

-- When changing this number, also change idris2_dispatch in runtime.c and
-- IDRIS2_MAX_TAILCALL_ARGS in runtime.h.
-- Increasing this number will worsen stack consumption and increase the codesize of idris2_dispatch_closure.
-- In C89, the maximum number of arguments is 31, so it should not be larger than 31. 127 is safe in C99, but I do not recommend it.
MaxExtractFunArgs : Nat
MaxExtractFunArgs = 16

integer_switch : List AConstAlt -> Bool
integer_switch [] = True
integer_switch (MkAConstAlt c _  :: _) =
    case c of
        (I x) => True
        (I8 x) => True
        (I16 x) => True
        (I32 x) => True
        (I64 x) => True
        (B8 x) => True
        (B16 x) => True
        (B32 x) => True
        (B64 x) => True
        (BI x) => True
        (Ch x) => True
        _ => False

||| The C value of a scrutinee `v` of the type of the constant `c`, for a
||| `switch` on fixed width integers (and characters).
unboxConst : Constant -> String -> String
unboxConst c v = case c of
    -- (the scrutinee may not have the type of the constants: comparisons
    -- give unboxed Bools for example)
    B8 _  => "idris2_extractUInt64(\{v})"
    B16 _ => "idris2_extractUInt64(\{v})"
    B32 _ => "idris2_extractUInt64(\{v})"
    Ch _  => "idris2_extractUInt64(\{v})"
    B64 _ => "(uint64_t)idris2_extractUInt64(\{v})"
    _     => "idris2_extractInt64(\{v})"

const2Integer : Constant -> Integer -> String
const2Integer c i =
    case c of
        (I x) => showIntMin x
        (I8 x) => "INT8_C(\{show x})"
        (I16 x) => "INT16_C(\{show x})"
        (I32 x) => "INT32_C(\{show x})"
        (I64 x) => showInt64Min x
        (BI x) => show x
        (Ch x) => escapeChar x
        (B8 x) => "UINT8_C(\{show x})"
        (B16 x) => "UINT16_C(\{show x})"
        (B32 x) => "UINT32_C(\{show x})"
        (B64 x) => "UINT64_C(\{show x})"
        _ => show i

||| The tag that a constructor has at run time: constructors without a tag, or
||| with one that does not fit in the 16 bits of the tag of
||| Idris2_Constructor, are told apart by their names.
conTag : Maybe Int -> Maybe Int
conTag (Just t) = if t >= 0 && t < 32768 then Just t else Nothing
conTag Nothing = Nothing

data TailPositionStatus = InTailPosition | NotInTailPosition

||| The application of a closure in tail position: returned at once, by a
||| jump where the C compiler can make one (IDRIS2_TAIL_APPLY, see runtime.h),
||| so that the runtime can jump to the function of the closure in turn.
tailApply : {auto oft : Ref OutfileText Output}
         -> {auto il : Ref IndentLevel Nat}
         -> FC -> String -> Core String
tailApply fc call = do
    emit fc "IDRIS2_TAIL_APPLY return \{call};"
    pure "NULL /* unreachable */"

||| The function takes as arguments the current ReuseMap and the constructors that will be used.
||| Returns constructor variables to remove and constructors to reuse.
dropUnusedReuseCons : ReuseMap -> SortedSet Name -> (List String, ReuseMap)
dropUnusedReuseCons reuseMap usedCons =
    -- if there is no constructor named by that name, then the reuse constructor is deleted
    let dropReuseMap = differenceMap reuseMap usedCons in
    let actualReuseMap = intersectionMap reuseMap usedCons in
    (values dropReuseMap, actualReuseMap)

||| The function takes as arguments the current owned vars and set vars that will be used.
||| Returns variables to remove and actual owned vars.
dropUnusedOwnedVars : Owned -> SortedSet AVar -> (List String, Owned)
dropUnusedOwnedVars owned usedVars =
    let actualOwned = intersection owned usedVars in
    let shouldDrop = difference owned actualOwned in
    (varName <$> Prelude.toList shouldDrop, actualOwned)

-- if the constructor is unique use it, otherwise add it to should drop vars and create null constructor
addReuseConstructor : {auto a : Ref ArgCounter Nat}
                    -> {auto oft : Ref OutfileText Output}
                    -> {auto il : Ref IndentLevel Nat}
                    -> ReuseMap
                    -> String
                    -> Name
                    -> List String
                    -> SortedSet Name
                    -> List String
                    -> SortedMap Name String
                    -> Core (List String, SortedMap Name String)
addReuseConstructor reuseMap sc conName conArgs consts shouldDrop actualReuseConsts =
    -- to avoid conflicts, we check that there is no constructor with the same name in reuse map
    -- we also check that the constructor will be used later and that the variable will be deleted
    -- (nullary constructors are not allocated, see `ACon`)
    if (isNothing $ SortedMap.lookup conName reuseMap)
       && not (null conArgs)
       && contains conName consts
       && (isJust $ find (== sc) shouldDrop) then do
        let constr = "constructor_" ++ !(getNextCounter)
        emit EmptyFC $ "Idris2_Constructor* " ++ constr ++ " = NULL;"
        -- If the constructor variable is unique (has 1 reference), then assign it for reuse
        emit EmptyFC $ "if (idris2_isUnique(" ++ sc ++ ")) {"
        increaseIndentation
        emit EmptyFC $ constr ++ " = (Idris2_Constructor*)" ++ sc ++ ";"
        -- (counted in a build with IDRIS2_REFC_STATS, see worker.h)
        emit EmptyFC "IDRIS2_STAT(reuseHit);"
        -- The fields that are not used any more were owned by the constructor
        -- that we take over: release them (the other branch does so when it
        -- releases the constructor).
        removeVars (filter (`elem` shouldDrop) conArgs)
        decreaseIndentation
        emit EmptyFC "}"
        -- Otherwise, delete and duplicate constructor variables
        emit EmptyFC "else {"
        increaseIndentation
        emit EmptyFC "IDRIS2_STAT(reuseMiss);"
        -- remove dup and remove if they are executed for the same argument
        dupVars (conArgs \\ shouldDrop)
        removeVars [sc]
        decreaseIndentation
        emit EmptyFC "}"
        pure (shouldDrop \\ (sc :: conArgs), insert conName constr actualReuseConsts)
    else if (isJust $ find (== sc) shouldDrop) && not (null conArgs) then do
        -- The constructor is not used any more (drop specialisation, as in
        -- Perceus): when it is unique, its fields are ours, and only its
        -- memory is given back; otherwise the fields that we use are shared.
        emit EmptyFC $ "if (idris2_isUnique(" ++ sc ++ ")) {"
        increaseIndentation
        removeVars (filter (`elem` shouldDrop) conArgs)
        emit EmptyFC $ "idris2_freeValue(" ++ sc ++ ");"
        decreaseIndentation
        emit EmptyFC "} else {"
        increaseIndentation
        dupVars (conArgs \\ shouldDrop)
        emit EmptyFC $ "idris2_dropSharedReference(" ++ sc ++ ");"
        decreaseIndentation
        emit EmptyFC "}"
        pure (shouldDrop \\ (sc :: conArgs), actualReuseConsts)
    else do
        dupVars $ conArgs \\ shouldDrop
        pure (shouldDrop \\ conArgs, actualReuseConsts)

||| The C arguments of the first application of `let var = f a in body`,
||| and the environment for `body`, as the translation of a `let` would give
||| them (see `letGeneric`).
applyFirst : Env -> Int -> ANF -> AVar -> AVar -> (String, String, Env)
applyFirst env var body f a =
    let usedVars = freeVariables body
        borrowVal = intersection env.owned (delete (ALocal var) usedVars)
        valueEnv = moveFromOwnedToBorrowed env borrowVal
    in (avarToC valueEnv f, avarToC valueEnv a,
        { owned := insert (ALocal var) borrowVal } env)

||| What the translation of an expression gives: a value (which may be a
||| pending call, in tail position), or a C integer (see Compiler.RefC.Unbox).
data Result = AValue TailPositionStatus | AnInt

mutual
    ||| The translation of an expression, as `r` says.
    cResult : {auto a : Ref ArgCounter Nat}
           -> {auto oft : Ref OutfileText Output}
           -> {auto il : Ref IndentLevel Nat}
           -> {auto e : Ref EnvTracker Env}
           -> {auto _ : Ref ConstDef (SortedMap Constant ConstDef)}
           -> ANF -> Result -> Core String
    cResult anf (AValue tailPosition) = cStatementsFromANF anf tailPosition
    cResult anf AnInt = cIntFromANF anf

    letGeneric : {auto a : Ref ArgCounter Nat}
              -> {auto oft : Ref OutfileText Output}
              -> {auto il : Ref IndentLevel Nat}
              -> {auto e : Ref EnvTracker Env}
              -> {auto _ : Ref ConstDef (SortedMap Constant ConstDef)}
              -> FC -> Int -> ANF -> ANF -> Result -> Core String
    letGeneric fc var value body r = do
        env <- get EnvTracker
        let usedVars = freeVariables body
        let borrowVal = intersection env.owned (delete (ALocal var) usedVars)
        let owned' = if contains (ALocal var) usedVars then insert (ALocal var) borrowVal else borrowVal
        let usedCons = usedConstructors value
        -- When translating value into C, we borrow variables that will be used in body
        let valueEnv = { reuseMap $= (`intersectionMap` usedCons) } (moveFromOwnedToBorrowed env borrowVal)
        put EnvTracker valueEnv
        emit fc $ "Idris2_Value * var_\{show var} = \{!(cStatementsFromANF value NotInTailPosition)};"
        unless (contains (ALocal var) usedVars) $ emit fc $ "idris2_removeReference(var_\{show var});"
        put EnvTracker ({ owned := owned', reuseMap $= (`differenceMap` usedCons) } env)
        cResult body r

    ||| A `let` of a variable that is a C integer (see Compiler.RefC.Unbox):
    ||| like `letGeneric`, but the variable is not a value that we own.
    letInt : {auto a : Ref ArgCounter Nat}
          -> {auto oft : Ref OutfileText Output}
          -> {auto il : Ref IndentLevel Nat}
          -> {auto e : Ref EnvTracker Env}
          -> {auto _ : Ref ConstDef (SortedMap Constant ConstDef)}
          -> FC -> Int -> ANF -> ANF -> Result -> Core String
    letInt fc var value body r = do
        env <- get EnvTracker
        let usedVars = freeVariables body
        let borrowVal = intersection env.owned (delete (ALocal var) usedVars)
        let usedCons = usedConstructors value
        let valueEnv = { reuseMap $= (`intersectionMap` usedCons) } (moveFromOwnedToBorrowed env borrowVal)
        put EnvTracker valueEnv
        emit fc $ "int64_t \{intVarName var} = \{!(cIntFromANF value)};"
        put EnvTracker ({ owned := borrowVal, reuseMap $= (`differenceMap` usedCons) } env)
        cResult body r

    ||| The C integer of an expression for which `intValued` holds.  The
    ||| variables that it uses up are released, as in `cStatementsFromANF`.
    cIntFromANF : {auto a : Ref ArgCounter Nat}
               -> {auto oft : Ref OutfileText Output}
               -> {auto il : Ref IndentLevel Nat}
               -> {auto e : Ref EnvTracker Env}
               -> {auto _ : Ref ConstDef (SortedMap Constant ConstDef)}
               -> ANF -> Core String
    cIntFromANF (AV fc v) = pure $ intOperand !(get EnvTracker) v
    cIntFromANF (APrimVal fc (I x)) = pure $ showIntMin x
    cIntFromANF (APrimVal fc (I64 x)) = pure $ showInt64Min x
    cIntFromANF (AOp fc _ op args) = do
        env <- get EnvTracker
        let resultVar = "primVar_" ++ !(getNextCounter)
        emit fc $ "int64_t \{resultVar} = \{intOpC op (map (intOperand env) args)};"
        removeVars $ map varName $ Prelude.toList $ intersection (fromList (toList args)) env.owned
        pure resultVar
    cIntFromANF (ALet fc var value body) = do
        env <- get EnvTracker
        if contains var env.unboxed
           then letInt fc var value body AnInt
           else letGeneric fc var value body AnInt
    cIntFromANF (AConstCase fc sc alts def) = constCase fc sc alts def AnInt
    cIntFromANF (ACrash fc _) = pure "0 /* CRASH */"
    cIntFromANF anf = throw $ InternalError "[refc] Not an Int expression: \{show anf}"

    concaseBody : {auto a : Ref ArgCounter Nat}
                 -> {auto e : Ref EnvTracker Env}
                 -> {auto oft : Ref OutfileText Output}
                 -> {auto il : Ref IndentLevel Nat}
                 -> {auto _ : Ref ConstDef (SortedMap Constant ConstDef)}
                 -> Env
                 -> String -> String -> List Int -> ANF -> Result
                 -> Core ()
    concaseBody env returnvar expr args body r = do
        increaseIndentation
        _ <- foldlC (\k, arg => do
            emit emptyFC "Idris2_Value *var_\{show arg} = ((Idris2_Constructor*)\{expr})->args[\{show k}];"
            pure (S k) ) 0 args

        let (shouldDrop, actualOwned) = dropUnusedOwnedVars env.owned (freeVariables body)
        let usedCons = usedConstructors body
        let (dropReuseCons, actualReuseMap) = dropUnusedReuseCons env.reuseMap usedCons
        put EnvTracker ({owned := actualOwned, reuseMap := actualReuseMap} env)
        removeVars shouldDrop
        removeReuseConstructors dropReuseCons
        emit emptyFC "\{returnvar} = \{!(cResult body r)};"
        decreaseIndentation

    cStatementsFromANF : {auto a : Ref ArgCounter Nat}
                      -> {auto oft : Ref OutfileText Output}
                      -> {auto il : Ref IndentLevel Nat}
                      -> {auto e : Ref EnvTracker Env}
                      -> {auto _ : Ref ConstDef (SortedMap Constant ConstDef)}
                      -> ANF
                      -> TailPositionStatus
                      -> Core String

    cStatementsFromANF (AV fc x) _ = pure $ avarToC !(get EnvTracker) x
    cStatementsFromANF (AAppName fc _ n args) tailPosition = do
        let nargs = length args
        env <- get EnvTracker
        if lookup (cName n) env.foreigns == Just nargs
           then foreignCall fc env n args
           else case tailPosition of
            InTailPosition =>
                if nargs > MaxExtractFunArgs
                   then makeClosure fc n args 0
                   else makeTailCall fc n args
            _ => if nargs > MaxExtractFunArgs
                then pure "idris2_trampoline(\{!(makeClosure fc n args 0)})"
                else do
                    env <- get EnvTracker
                    let args' = avarsToC env.unboxed env.owned args
                    pure "idris2_trampoline(\{cName n}(\{concat $ intersperse ", " args'}))"
      where
        -- A full application of a foreign function calls the variant of
        -- its wrapper that borrows the arguments (see `createCFunctions`),
        -- like a primitive operation: the arguments are passed as they are,
        -- and those that we own are released after.  This saves taking and
        -- releasing a reference to each of them, which are atomic operations
        -- on a value that threads share (a mutex, a channel).  The result is
        -- a value, never a pending tail call, even in tail position.
        foreignCall : FC -> Env -> Name -> List AVar -> Core String
        foreignCall fc env n args = do
            let call = "\{cName n}_borrow(\{concat $ intersperse ", " (map varName args)})"
            let owned = Prelude.toList $ intersection (fromList args) env.owned
            if null owned
               then pure call
               else do
                 let resultVar = "ffiVar_" ++ !(getNextCounter)
                 emit fc $ "Idris2_Value *" ++ resultVar ++ " = " ++ call ++ ";"
                 removeVars (map varName owned)
                 pure resultVar

    cStatementsFromANF (AUnderApp fc n missing args) _ = makeClosure fc n args missing
    cStatementsFromANF (AApp fc _ closure arg) tailPosition = do
       env <- get EnvTracker
       case tailPosition of
           NotInTailPosition =>
             pure "idris2_apply_closure(\{avarToC env closure}, \{avarToC env arg})"
           InTailPosition =>
             tailApply fc "idris2_tailcall_apply_closure(\{avarToC env closure}, \{avarToC env arg})"

    -- `let v = f a in let w = v b in body`, where `v` is not used anywhere
    -- else, applies `f` to both arguments at once (and likewise when the
    -- body is `v b`), so that no partial application is made in between.
    cStatementsFromANF (ALet fc var (AApp fc1 l1 f a) (ALet fc2 var2 (AApp fc3 l3 (ALocal v) b) body2)) tailPosition
      = if v == var && b /= ALocal var && not (contains (ALocal var) (freeVariables body2))
           then do
             env <- get EnvTracker
             let (fStr, aStr, env1) = applyFirst env var (ALet fc2 var2 (AApp fc3 l3 (ALocal v) b) body2) f a
             let usedVars2 = freeVariables body2
             let borrowVal2 = intersection env1.owned (delete (ALocal var2) usedVars2)
             let owned2 = if contains (ALocal var2) usedVars2 then insert (ALocal var2) borrowVal2 else borrowVal2
             let bStr = avarToC (moveFromOwnedToBorrowed env1 borrowVal2) b
             emit fc2 $ "Idris2_Value * var_\{show var2} = idris2_apply_closure2(\{fStr}, \{aStr}, \{bStr});"
             unless (contains (ALocal var2) usedVars2) $ emit fc2 $ "idris2_removeReference(var_\{show var2});"
             put EnvTracker ({ owned := owned2 } env1)
             cStatementsFromANF body2 tailPosition
           else letGeneric fc var (AApp fc1 l1 f a) (ALet fc2 var2 (AApp fc3 l3 (ALocal v) b) body2) (AValue tailPosition)
    cStatementsFromANF (ALet fc var (AApp fc1 l1 f a) (AApp fc2 l2 (ALocal v) b)) tailPosition
      = if v == var && b /= ALocal var
           then do
             env <- get EnvTracker
             let (fStr, aStr, env1) = applyFirst env var (AApp fc2 l2 (ALocal v) b) f a
             put EnvTracker env1
             case tailPosition of
                 NotInTailPosition => pure "idris2_apply_closure2(\{fStr}, \{aStr}, \{avarToC env1 b})"
                 InTailPosition => tailApply fc "idris2_tailcall_apply_closure2(\{fStr}, \{aStr}, \{avarToC env1 b})"
           else letGeneric fc var (AApp fc1 l1 f a) (AApp fc2 l2 (ALocal v) b) (AValue tailPosition)
    cStatementsFromANF (ALet fc var value body) tailPosition = do
        env <- get EnvTracker
        if contains var env.unboxed
           then letInt fc var value body (AValue tailPosition)
           else letGeneric fc var value body (AValue tailPosition)

    cStatementsFromANF (ACon fc n coninfo tag args) _ = do
        if coninfo == NIL || coninfo == NOTHING || coninfo == ZERO || coninfo == UNIT
            then pure "(NULL /* \{show n} */)"
            else case (args, tag) of
              ([], Just t) =>
                if t >= 0 && t < 256
                   -- an immortal value of the runtime, nothing to allocate
                   then pure "idris2_nullaryConstructor(\{show t}) /* \{show n} */"
                   else newConstructor
              _ => newConstructor
      where
        newConstructor : Core String
        newConstructor = do
                env <- get EnvTracker
                let createNewConstructor = case conTag tag of
                      Just t => " = idris2_newConstructor(\{show (length args)}, \{show t});"
                      Nothing => " = idris2_newNamedConstructor(\{show (length args)}, idris2_constr_\{cName n});"

                emit fc " // constructor \{show n}"
                constr <- case SortedMap.lookup n $ reuseMap env of
                    Just constr => do
                        emit fc "if (! \{constr}) {"
                        increaseIndentation
                        emit fc $ constr ++ createNewConstructor
                        decreaseIndentation
                        emit fc "}"
                        pure constr
                    Nothing => do
                        let constr = "constructor_\{!(getNextCounter)}"
                        emit fc $ "Idris2_Constructor* " ++ constr ++ createNewConstructor
                        pure constr
                fillArgs env "\{constr}->args" args 0
                pure "(Idris2_Value*)\{constr}"

    cStatementsFromANF (AOp fc _ op args) _ = do
        env <- get EnvTracker
        let resultVar = "primVar_" ++ !(getNextCounter)
        -- The primitive operations borrow their arguments, so the arguments
        -- are passed as they are, and those that we own are released after.
        -- An operation on Ints of which some are C integers (see
        -- Compiler.RefC.Unbox) is done on C integers.
        let value = if intOp op && any (isUnboxedIn env.unboxed) args
                       then let e = intOpC op (map (intOperand env) args) in
                            if isComparison op then "idris2_mkBool(\{e})"
                                               else "idris2_mkInt64(\{e})"
                       else cOp op (map varName args)
        emit fc $ "Idris2_Value *" ++ resultVar ++ " = " ++ value ++ ";"
        removeVars $ map varName $ Prelude.toList $ intersection (fromList (toList args)) env.owned
        pure resultVar

    cStatementsFromANF (AExtPrim fc _ p args) _ = do
        let prims : List String =
            ["prim__newIORef", "prim__readIORef", "prim__writeIORef", "prim__newArray",
             "prim__arrayGet", "prim__arraySet", "prim__getField", "prim__setField",
             "prim__os", "prim__codegen", "prim__onCollect", "prim__onCollectAny" ]
        case p of
            NS _ (UN (Basic pn)) =>
               unless (elem pn prims) $ throw $ InternalError $ "[refc] Unknown primitive: " ++ cName p
            _ => throw $ InternalError $ "[refc] Unknown primitive: " ++ cName p
        env <- get EnvTracker
        let resultVar = "primVar_" ++ !(getNextCounter)
        emit fc $ "// call to external primitive " ++ cName p
        emit fc $ "Idris2_Value *\{resultVar} = idris2_\{cName p}(" ++ showSep ", " (map varName args) ++ ");"
        -- The primitives borrow their arguments (they take a reference to
        -- whatever they keep), so the arguments we own are released here.
        removeVars $ map varName $ Prelude.toList $ intersection (fromList args) env.owned
        pure resultVar

    cStatementsFromANF (AConCase fc sc alts mDef) tailPosition = do
        let sc' = varName sc
        switchReturnVar <- getNewVarThatWillNotBeFreedAtEndOfBlock
        emit fc "Idris2_Value * \{switchReturnVar} = NULL;"
        env <- get EnvTracker
        _ <- foldlC (\els, (MkAConAlt name coninfo tag args body) => do
            let erased = coninfo == NIL || coninfo == NOTHING || coninfo == ZERO || coninfo == UNIT
            if erased then emit emptyFC "\{els}if (NULL == \{sc'} /* \{show name} \{show coninfo} */) {"
                else if coninfo == CONS || coninfo == JUST || coninfo == SUCC
                then emit emptyFC "\{els}if (NULL != \{sc'} /* \{show name} \{show coninfo} */) {"
                else do
                    case conTag tag of
                        Nothing   => emit emptyFC "\{els}if (! strcmp(idris2_constructorName(\{sc'}), idris2_constr_\{cName name})) {"
                        Just tag' => emit emptyFC "\{els}if (((Idris2_Constructor *)\{sc'})->tag == \{show tag'} /* \{show name} */) {"

            let conArgs = ALocal <$> args
            let ownedWithArgs = union (fromList conArgs) $ if erased then delete sc env.owned else env.owned
            let usedVars = freeVariables body
            let (shouldDrop, actualOwned) = dropUnusedOwnedVars ownedWithArgs usedVars
            let usedCons = usedConstructors body
            let (dropReuseCons, actualReuseMap) = dropUnusedReuseCons env.reuseMap usedCons
            -- A field is read when the body uses it, or when the scrutinee is
            -- dropped (addReuseConstructor then releases the unused fields);
            -- otherwise it would be an unused variable.
            let scDropped = isJust (find (== sc') shouldDrop)
            increaseIndentation
            _ <- foldlC (\k, arg => do
                when (scDropped || contains (ALocal arg) usedVars) $
                  emit emptyFC "Idris2_Value *var_\{show arg} = ((Idris2_Constructor*)\{sc'})->args[\{show k}];"
                pure (S k) ) 0 args
            (shouldDrop, actualReuseMap) <- addReuseConstructor env.reuseMap sc' name (varName <$> conArgs) usedCons shouldDrop actualReuseMap
            removeVars shouldDrop
            removeReuseConstructors dropReuseCons
            put EnvTracker ({owned := actualOwned, reuseMap := actualReuseMap} env)
            emit emptyFC "\{switchReturnVar} = \{!(cStatementsFromANF body tailPosition)};"
            decreaseIndentation
            pure "} else ") "" alts

        case mDef of
            Nothing => pure ()
            Just body => do
                emit emptyFC "} else {"
                concaseBody env switchReturnVar "" [] body (AValue tailPosition)
        emit emptyFC "}"
        pure switchReturnVar

    cStatementsFromANF (AConstCase fc sc alts def) tailPosition
        = constCase fc sc alts def (AValue tailPosition)

    cStatementsFromANF (APrimVal fc (I x)) tailPosition = cStatementsFromANF (APrimVal fc (I64 $ cast x)) tailPosition
    cStatementsFromANF (APrimVal fc c@(BI x)) _
      = if x >= -2147483648 && x <= 2147483647
           -- unboxed on 64 bit platforms
           then pure $ if x >= 0 && x < 100
                  then "(idris2_fitsSmallInteger(\{show x}) ? idris2_mkSmallInteger(\{show x}) : idris2_getPredefinedInteger(\{show x}))"
                  else "idris2_mkIntegerFromInt64(INT64_C(\{show x}))"
           else boxed
      where
        boxed : Core String
        boxed = do
             -- A large Integer literal is made once, the first time that it
             -- is needed, instead of being parsed every time.
             constdefs <- get ConstDef
             cdef <- case lookup c constdefs of
                          Just cdef => pure cdef
                          Nothing => do
                            let cdef = CDBI !(getNextCounter)
                            put ConstDef $ insert c cdef constdefs
                            pure cdef
             pure "idris2_integerConstant(&\{constantName cdef}, \"\{show x}\")"
    cStatementsFromANF (APrimVal fc c) _ = do
      constdefs <- get ConstDef
      case lookup c constdefs of
           Just cdef => pure "((Idris2_Value*)&\{constantName cdef})" -- the constant already booked.
           Nothing => dyngen
     where
        orStagen : ConstDef -> Core String
        orStagen cdef = do -- booking the constant to generate later
            constdefs <- get ConstDef
            put ConstDef $ insert c cdef constdefs
            pure "((Idris2_Value*)&\{constantName cdef})" -- the constant already booked.
        dyngen : Core String
        dyngen = case c of
            I x => if x >= -2147483648 && x <= 2147483647
                then pure "idris2_mkInt64(INT64_C(\{show x}))" -- unboxed on 64 bit platforms
                else orStagen $ CDI64 $ cCleanString $ show x
            I8 x  => pure "idris2_mkInt8(INT8_C(\{show x}))"
            I16 x => pure "idris2_mkInt16(INT16_C(\{show x}))"
            I32 x => pure "idris2_mkInt32(INT32_C(\{show x}))"
            I64 x => if x >= -2147483648 && x <= 2147483647
                then pure "idris2_mkInt64(INT64_C(\{show x}))"
                else orStagen $ CDI64 $ cCleanString $ show x
            BI x => if x >= 0 && x < 100
                then pure "idris2_getPredefinedInteger(\{show x})"
                else pure "idris2_mkIntegerLiteral(\"\{show x}\")"
            B8 x  => pure "idris2_mkBits8(UINT8_C(\{show x}))"
            B16 x => pure "idris2_mkBits16(UINT16_C(\{show x}))"
            B32 x => pure "idris2_mkBits32(UINT32_C(\{show x}))"
            B64 x => if x >= 0 && x <= 4294967295
               then pure "idris2_mkBits64(UINT64_C(\{show x}))"
               else orStagen $ CDB64 $ show x
            Db x => orStagen $ CDDb $ cCleanString $ show x
            Ch x  => pure "idris2_mkChar(\{escapeChar x})"
            Str _ => orStagen $ CDStr !(getNextCounter)
            PrT t => pure $ cPrimType t
            WorldVal => pure "(NULL /* World */)"

    cStatementsFromANF (AErased fc) _ = pure "NULL"
    cStatementsFromANF (ACrash fc x) _ = pure "(NULL /* CRASH */)"

    ||| A `case` on constants, which gives a value or a C integer.  A
    ||| scrutinee that is a C integer is switched on as it is.
    constCase : {auto a : Ref ArgCounter Nat}
             -> {auto oft : Ref OutfileText Output}
             -> {auto il : Ref IndentLevel Nat}
             -> {auto e : Ref EnvTracker Env}
             -> {auto _ : Ref ConstDef (SortedMap Constant ConstDef)}
             -> FC -> AVar -> List AConstAlt -> Maybe ANF -> Result
             -> Core String
    constCase fc sc alts def r = do
        let sc' = varName sc
        switchReturnVar <- getNewVarThatWillNotBeFreedAtEndOfBlock
        case r of
             AnInt => emit fc "int64_t \{switchReturnVar} = 0;"
             AValue _ => emit fc "Idris2_Value *\{switchReturnVar} = NULL;"
        env <- get EnvTracker
        case alts of
            [] => do
                -- only a default
                emit emptyFC "{"
                traverse_ (\body => concaseBody env switchReturnVar "" [] body r) (toList def)
                emit emptyFC "}"
            (MkAConstAlt (BI _) _ :: _) => do
                -- Integers are compared without converting the scrutinee,
                -- which may not fit in a machine integer.  The conditions
                -- are made first: large literals may need statements.
                conds <- traverse (\(MkAConstAlt c body) => pure (!(integerEq sc' c), body)) alts
                _ <- foldlC (\els, (cond, body) => do
                    emit emptyFC "\{els}if (\{cond}) {"
                    concaseBody env switchReturnVar "" [] body r
                    pure "} else ") "" conds
                ifChainDefault env switchReturnVar
            (MkAConstAlt c _ :: _) =>
              if integer_switch alts
                then do
                  emit emptyFC "switch (\{scrutinee env c}) {"
                  for_ alts $ \(MkAConstAlt c' body) => do
                      emit emptyFC "case \{const2Integer c' 0}: {"
                      concaseBody env switchReturnVar "" [] body r
                      emit emptyFC "  break;"
                      emit emptyFC "}"
                  emit emptyFC "default: {"
                  traverse_ (\body => concaseBody env switchReturnVar "" [] body r) (toList def)
                  emit emptyFC "}"
                  emit emptyFC "}"
                else do
                  _ <- foldlC (\els, (MkAConstAlt c body) => do
                      case c of
                          Str x => emit emptyFC "\{els}if (idris2_eqStringLiteral(\{sc'}, \{cStringQuoted x})) {"
                          Db  x => emit emptyFC "\{els}if (((Idris2_Double *)\{sc'})->d == \{cDouble x}) {"
                          x => throw $ InternalError "[refc] AConstCase : unsupported type. \{show fc} \{show x}"
                      concaseBody env switchReturnVar "" [] body r
                      pure "} else ") "" alts
                  ifChainDefault env switchReturnVar
        pure switchReturnVar
      where
        scrutinee : Env -> Constant -> String
        scrutinee env c = if isUnboxedIn env.unboxed sc then intOperand env sc
                                                     else unboxConst c (varName sc)

        integerEq : String -> Constant -> Core String
        integerEq v (BI x)
          = if x >= -2147483648 && x <= 2147483647
               then pure "idris2_eqIntegerSmall(\{v}, INT64_C(\{show x}))"
               else do lit <- cStatementsFromANF (APrimVal fc (BI x)) NotInTailPosition
                       pure "idris2_cmpInteger(\{v}, \{lit}) == 0"
        integerEq v c = throw $ InternalError "[refc] AConstCase : mixed Integer case. \{show fc} \{show c}"

        ifChainDefault : Env -> String -> Core ()
        ifChainDefault env switchReturnVar = do
          case def of
              Nothing => pure ()
              Just body => do
                  emit emptyFC "} else {"
                  concaseBody env switchReturnVar "" [] body r
          emit emptyFC "}"


addCommaToList : List String -> List String
addCommaToList [] = []
addCommaToList (x :: xs) = ("  " ++ x) :: map (", " ++) xs


getArgsNrList : List ty -> Nat -> List Nat
getArgsNrList [] _ = []
getArgsNrList (x :: xs) k = k :: getArgsNrList xs (S k)


cTypeOfCFType : CFType -> String
cTypeOfCFType CFUnit          = "void"
cTypeOfCFType CFInt           = "int64_t"
cTypeOfCFType CFInt8          = "int8_t"
cTypeOfCFType CFInt16         = "int16_t"
cTypeOfCFType CFInt32         = "int32_t"
cTypeOfCFType CFInt64         = "int64_t"
cTypeOfCFType CFUnsigned8     = "uint8_t"
cTypeOfCFType CFUnsigned16    = "uint16_t"
cTypeOfCFType CFUnsigned32    = "uint32_t"
cTypeOfCFType CFUnsigned64    = "uint64_t"
cTypeOfCFType CFString        = "char *"
-- Integers are passed as the boxed `Idris2_Value *` (an `Idris2_Integer`)
cTypeOfCFType CFInteger       = "Idris2_Value *"
cTypeOfCFType CFDouble        = "double"
cTypeOfCFType CFChar          = "char"
cTypeOfCFType CFPtr           = "void *"
cTypeOfCFType CFGCPtr         = "void *"
cTypeOfCFType CFBuffer        = "void *"
cTypeOfCFType CFWorld         = "void *"
cTypeOfCFType (CFFun x y)     = "void *"
cTypeOfCFType (CFIORes x)     = "void *"
cTypeOfCFType (CFStruct x ys) = "void *"
cTypeOfCFType (CFUser x ys)   = "void *"
cTypeOfCFType CFForeignObj    = "void *"
cTypeOfCFType n = assert_total $ idris_crash ("INTERNAL ERROR: Unknown FFI type in C backend: " ++ show n)

varNamesFromList : List ty -> Nat -> List String
varNamesFromList str k = map (("var_" ++) . show) (getArgsNrList str k)

createFFIArgList : List CFType
                -> Core $ List (String, String, CFType)
createFFIArgList cftypeList = do
    let sList = map cTypeOfCFType cftypeList
    let varList = varNamesFromList cftypeList 1
    pure $ zip3 sList varList cftypeList

emitFDef : {auto oft : Ref OutfileText Output}
        -> {auto il : Ref IndentLevel Nat}
        -> (funcName : String) -- the C name
        -> (arglist:List (String, String, CFType))
        -> Core ()
emitFDef funcName [] = emit EmptyFC $ "Idris2_Value *" ++ funcName ++ "(void)"
emitFDef funcName ((varType, varName, varCFType) :: xs) = do
    emit EmptyFC $ "Idris2_Value *" ++ funcName
    emit EmptyFC "("
    increaseIndentation
    emit EmptyFC $ "  Idris2_Value *" ++ varName
    traverse_ (\(varType, varName, varCFType) => emit EmptyFC $ ", Idris2_Value *" ++ varName) xs
    decreaseIndentation
    emit EmptyFC ")"

-- Generic C parameter or RefC specific parameter
data CLang = CLangC | CLangRefC

extractValue : (cLang : CLang) -> (cfType:CFType) -> (varName:String) -> String
extractValue _ CFUnit           varName = "NULL"
extractValue _ CFInt            varName = "(idris2_vp_to_Int64(" ++ varName ++ "))"
extractValue _ CFInt8           varName = "(idris2_vp_to_Int8(" ++ varName ++ "))"
extractValue _ CFInt16          varName = "(idris2_vp_to_Int16(" ++ varName ++ "))"
extractValue _ CFInt32          varName = "(idris2_vp_to_Int32(" ++ varName ++ "))"
extractValue _ CFInt64          varName = "(idris2_vp_to_Int64(" ++ varName ++ "))"
extractValue _ CFUnsigned8      varName = "(idris2_vp_to_Bits8(" ++ varName ++ "))"
extractValue _ CFUnsigned16     varName = "(idris2_vp_to_Bits16(" ++ varName ++ "))"
extractValue _ CFUnsigned32     varName = "(idris2_vp_to_Bits32(" ++ varName ++ "))"
extractValue _ CFUnsigned64     varName = "(idris2_vp_to_Bits64(" ++ varName ++ "))"
-- The functions of the `RefC` calling convention take strings as Idris values
-- (which may contain NUL characters); C functions get a C string.
extractValue CLangRefC CFString varName = "(Idris2_Value*)" ++ varName
extractValue _ CFString         varName = "((Idris2_String*)" ++ varName ++ ")->str"
extractValue _ CFInteger        varName = "(Idris2_Value*)" ++ varName
extractValue _ CFDouble         varName = "(idris2_vp_to_Double(" ++ varName ++ "))"
extractValue _ CFChar           varName = "(idris2_vp_to_Char(" ++ varName ++ "))"
extractValue _ CFPtr            varName = "((Idris2_Pointer*)" ++ varName ++ ")->p"
extractValue _ CFGCPtr          varName = "((Idris2_GCPointer*)" ++ varName ++ ")->p->p"
extractValue CLangC    CFBuffer varName = "((Idris2_Buffer*)" ++ varName ++ ")->buffer->data"
extractValue CLangRefC CFBuffer varName = "((Idris2_Buffer*)" ++ varName ++ ")->buffer"
extractValue _ CFWorld          _       = "(Idris2_Value *)NULL"
extractValue _ (CFFun x y)      varName = "(Idris2_Closure*)" ++ varName
extractValue c (CFIORes x)      varName = extractValue c x varName
extractValue _ (CFStruct x xs)  varName = assert_total $ idris_crash ("INTERNAL ERROR: Struct access not implemented: " ++ varName)
-- not really total but this way this internal error does not contaminate everything else
extractValue _ (CFUser x xs)    varName = "(Idris2_Value*)" ++ varName
extractValue _ CFForeignObj     varName = "(Idris2_Value*)" ++ varName
extractValue _ n _ = assert_total $ idris_crash ("INTERNAL ERROR: Unknown FFI type in C backend: " ++ show n)

packCFType : (cfType:CFType) -> (varName:String) -> String
packCFType CFUnit          varName = "((Idris2_Value *)NULL)"
packCFType CFInt           varName = "idris2_mkInt64(" ++ varName ++ ")"
packCFType CFInt8          varName = "idris2_mkInt8(" ++ varName ++ ")"
packCFType CFInt16         varName = "idris2_mkInt16(" ++ varName ++ ")"
packCFType CFInt32         varName = "idris2_mkInt32(" ++ varName ++ ")"
packCFType CFInt64         varName = "idris2_mkInt64(" ++ varName ++ ")"
packCFType CFUnsigned64    varName = "idris2_mkBits64(" ++ varName ++ ")"
packCFType CFUnsigned32    varName = "idris2_mkBits32(" ++ varName ++ ")"
packCFType CFUnsigned16    varName = "idris2_mkBits16(" ++ varName ++ ")"
packCFType CFUnsigned8     varName = "idris2_mkBits8(" ++ varName ++ ")"
packCFType CFString        varName = "idris2_mkString(" ++ varName ++ ")"
packCFType CFInteger       varName = varName
packCFType CFDouble        varName = "idris2_mkDouble(" ++ varName ++ ")"
packCFType CFChar          varName = "idris2_mkChar(" ++ varName ++ ")"
packCFType CFPtr           varName = "idris2_makePointer(" ++ varName ++ ")"
packCFType CFGCPtr         varName = "idris2_makePointer(" ++ varName ++ ")"
packCFType CFBuffer        varName = "idris2_makeBuffer(" ++ varName ++ ")"
packCFType CFWorld         _       = "(Idris2_Value *)NULL"
packCFType (CFFun x y)     varName = "makeFunction(" ++ varName ++ ")"
packCFType (CFIORes x)     varName = packCFType x varName
packCFType (CFStruct x xs) varName = "makeStruct(" ++ varName ++ ")"
packCFType (CFUser x xs)   varName = varName
packCFType CFForeignObj    varName = varName
packCFType n _ = assert_total $ idris_crash ("INTERNAL ERROR: Unknown FFI type in C backend: " ++ show n)

||| The result of a foreign function.  A String returned by a function of the
||| `RefC` calling convention is an Idris value (a new reference); one from a
||| plain C function is a `char *`, which is copied.
packFFIResult : CLang -> (cfType : CFType) -> (varName : String) -> String
packFFIResult CLangRefC CFString    varName = varName
packFFIResult c         (CFIORes x) varName = packFFIResult c x varName
packFFIResult _         t           varName = packCFType t varName

||| The C type of the result of a foreign function (see `packFFIResult`).
cResultType : CLang -> CFType -> String
cResultType CLangRefC CFString = "Idris2_Value *"
cResultType _ t = cTypeOfCFType t

discardLastArgument : List ty -> List ty
discardLastArgument [] = []
discardLastArgument xs@(_ :: _) = init xs

additionalFFIStub : Name -> List CFType -> CFType -> String
additionalFFIStub name argTypes (CFIORes retType) = additionalFFIStub name (discardLastArgument argTypes) retType
additionalFFIStub name argTypes retType =
    cTypeOfCFType retType ++
    " (*" ++ cName name ++ ")(" ++
    (concat $ intersperse ", " $ map cTypeOfCFType argTypes) ++ ") = (void*)idris2_missing_ffi;\n"

||| The parameters `params` of the function `n` (in its compiled form) that have
||| the type `Int` or `Int64`.  They are its arguments that are not dropped
||| (see `mkDropSubst`), in order: if the type has fewer arguments than the
||| function (whose result is a function, by a name), none are given.
intParams : {auto c : Ref Ctxt Defs} -> Name -> List Int -> Core (SortedSet Int)
intParams n params = do
    defs <- get Ctxt
    Just gdef <- lookupCtxtExact n (gamma defs)
      | Nothing => pure empty
    let tys = binders 0 (eraseArgs gdef) (type gdef)
    pure $ if length params > length tys
              then empty
              else fromList (map fst (filter snd (zip params tys)))
  where
    isInt : Term vs -> Bool
    isInt (PrimVal _ (PrT t)) = isIntType t
    isInt _ = False

    binders : Nat -> NatSet -> Term vs -> List Bool
    binders i es (Bind _ _ (Pi _ rig _ ty) sc)
        = let rest = binders (S i) es sc in
              if i `elem` es then rest else (isInt ty && rig /= erased) :: rest
    binders _ _ _ = []

createCFunctions : {auto c : Ref Ctxt Defs}
                -> {auto fo : Ref Foreigns (SortedMap String Nat)}
                -> {auto a : Ref ArgCounter Nat}
                -> {auto _ : Ref ConstDef (SortedMap Constant ConstDef)}
                -> {auto f : Ref FunctionDefinitions (List String)}
                -> {auto oft : Ref OutfileText Output}
                -> {auto il : Ref IndentLevel Nat}
                -> {auto h : Ref HeaderFiles (SortedSet String)}
                -> {default [] additionalFFILangs : List String}
                -> Name
                -> ANFDef
                -> Core ()
createCFunctions n (MkAFun args anf) = do
    cn <- cName <$> getFullName n
    let nargs = length args
    let params = if nargs == 0 then "(void)"
               else if nargs > MaxExtractFunArgs then "(Idris2_Value *var_arglist[\{show nargs}])"
               else ("\n(\n" ++ (showSep "\n" $ addCommaToList (map (\i =>  "  Idris2_Value * var_" ++ (show i)) args))) ++ "\n)"
    let fn = "Idris2_Value *\{cn}" ++ params
    update FunctionDefinitions $ \otherDefs => (fn ++ ";\n") :: otherDefs
    -- A definition without arguments (a constant) is evaluated once, the
    -- first time that it is needed, like the top level constants of the
    -- Scheme backends: its body is in a function of its own, and its value is
    -- kept for good (it is immortal).
    let body = if nargs == 0
                  then "static Idris2_Value *\{cn}_constant" ++ params
                  else fn

    let argsVars = fromList $ ALocal <$> args
    let bodyFreeVars = freeVariables anf
    let shouldDrop = difference argsVars bodyFreeVars
    let argsNrs = getArgsNrList args Z
    emit EmptyFC body
    emit EmptyFC "{"
    increaseIndentation
    when (nargs > MaxExtractFunArgs) $ do
      _ <- foldlC (\i, j => do
         emit EmptyFC "Idris2_Value *var_\{show j} = var_arglist[\{show i}];"
         pure $ i + 1) 0 args
      pure ()
    let loops = nargs > 0 && nargs <= MaxExtractFunArgs
                && hasSelfTailCall cn nargs anf
    -- The variables that are C integers (see Compiler.RefC.Unbox): the
    -- parameters among them are unboxed once, before the loop starts.
    foreigns <- get Foreigns
    let calls = MkCalls (\m, as => loops && cName m == cn && length as == nargs)
                        (\m, as => lookup (cName m) foreigns == Just (length as))
    unboxed <- if hasIntOp anf
                  then unboxedVars calls loops args <$> intParams n args <*> pure anf
                  else pure empty
    let unboxedParams = filter (`contains` unboxed) args
    for_ unboxedParams $ \p => do
      emit EmptyFC "int64_t \{intVarName p} = idris2_vp_to_Int64(var_\{show p});"
      emit EmptyFC "idris2_removeReference(var_\{show p});"
    when loops $ emit EmptyFC "idris2_self_entry: ;"
    removeVars (varName <$> Prelude.toList shouldDrop)
    _ <- newRef EnvTracker (MkEnv (bodyFreeVars `difference` fromList (ALocal <$> unboxedParams))
                              empty
                              (if loops then Just (cn, args) else Nothing)
                              -- (many arguments are passed in an array)
                              (if nargs > MaxExtractFunArgs then 1 else nargs)
                              foreigns unboxed)
    emit EmptyFC $ "return \{!(cStatementsFromANF anf InTailPosition)};"
    decreaseIndentation
    emit EmptyFC  "}\n"
    -- (idris2_constantValue makes it once, even with threads running in
    -- parallel.)
    when (nargs == 0) $ do
      emit EmptyFC fn
      emit EmptyFC "{"
      emit EmptyFC "  static Idris2_Constant constant;"
      emit EmptyFC "  return idris2_constantValue(&constant, \{cn}_constant);"
      emit EmptyFC "}\n"
    emit EmptyFC  ""
    pure ()


createCFunctions n (MkACon tag arity nt) =
  case conTag tag of
    Nothing => do
      let n' = cName n
      -- extern: in a generated file compiled in parts (see
      -- generateCSourceFile) the definition is in one part only.
      update FunctionDefinitions $ \otherDefs => "extern char const idris2_constr_\{n'}[];" :: otherDefs
      emit EmptyFC "char const idris2_constr_\{n'}[] = \{cStringQuoted $ show n};"
    Just _ =>
      emit EmptyFC $ ( "// \{show n} Constructor tag " ++ show tag ++ " arity " ++ show arity) -- Nothing to compile here


createCFunctions n (MkAForeign ccs fargs ret) = do
  case parseCC (additionalFFILangs ++ ["RefC", "C"]) ccs of
      Just (lang, fctForeignName :: extLibOpts) => do
          let cLang = if lang == "RefC"
                         then CLangRefC
                         else CLangC
          let isStandardFFI = elem lang $ the (List String) ["RefC", "C"]
          let fctName = if isStandardFFI
                           then UN $ Basic $ fctForeignName
                           else NS (mkNamespace lang) n
          if isStandardFFI
             then case extLibOpts of
                      [lib, header] => update HeaderFiles $ insert header
                      _ => pure ()
             else emit EmptyFC $ additionalFFIStub fctName fargs ret
          let params = "(" ++ showSep ", " (replicate (length fargs) "Idris2_Value *") ++ ");"
          let fnDef = "Idris2_Value *" ++ cName n ++ params
          let borrowDef = "Idris2_Value *" ++ cName n ++ "_borrow" ++ params
          update FunctionDefinitions $ \otherDefs => (fnDef ++ "\n") :: (borrowDef ++ "\n") :: otherDefs
          typeVarNameArgList <- createFFIArgList fargs
          let argNames = (\(_, varName, _) => varName) <$> typeVarNameArgList

          -- The wrapper, which takes the arguments over (as the other
          -- functions do), for closures and partial applications
          emitFDef (cName n) typeVarNameArgList
          emit EmptyFC "{"
          increaseIndentation
          emit EmptyFC $ "Idris2_Value *retVal = " ++ cName n ++ "_borrow(" ++ showSep ", " argNames ++ ");"
          removeVars argNames
          emit EmptyFC "return retVal;"
          decreaseIndentation
          emit EmptyFC "}"

          -- The variant that borrows the arguments, for full applications
          -- (see `foreignCall`)
          emitFDef (cName n ++ "_borrow") typeVarNameArgList
          emit EmptyFC "{"
          increaseIndentation
          emit EmptyFC $ " // ffi call to " ++ cName fctName
          case ret of
              CFIORes CFUnit => do
                  emit EmptyFC $ cName fctName
                              ++ "("
                              ++ showSep ", " (map (\(_, vn, vt) => extractValue cLang vt vn) (discardLastArgument typeVarNameArgList))
                              ++ ");"
                  emit EmptyFC "return NULL;"
              CFIORes ret => do
                  emit EmptyFC $ cResultType cLang ret ++ " retVal = " ++ cName fctName
                              ++ "("
                              ++ showSep ", " (map (\(_, vn, vt) => extractValue cLang vt vn) (discardLastArgument typeVarNameArgList))
                              ++ ");"
                  emit EmptyFC $ "return (Idris2_Value*)" ++ packFFIResult cLang ret "retVal" ++ ";"
              _ => do
                  emit EmptyFC $ cResultType cLang ret ++ " retVal = " ++ cName fctName
                              ++ "("
                              ++ showSep ", " (map (\(_, vn, vt) => extractValue cLang vt vn) typeVarNameArgList)
                              ++ ");"
                  emit EmptyFC $ "return (Idris2_Value*)" ++ packFFIResult cLang ret "retVal" ++ ";"

          decreaseIndentation
          emit EmptyFC "}"
      _ => throw $ InternalError "[refc] FFI not found for \{cName n}"
          -- not really total but this way this internal error does not contaminate everything else

createCFunctions n (MkAError exp) = throw $ InternalError "[refc] Error with expression: \{show exp}"
-- not really total but this way this internal error does not contaminate everything else


header : {auto f : Ref FunctionDefinitions (List String)}
      -> {auto o : Ref OutfileText Output}
      -> {auto il : Ref IndentLevel Nat}
      -> {auto h : Ref HeaderFiles (SortedSet String)}
      -> {auto _ : Ref ConstDef (SortedMap Constant ConstDef)}
      -> Core ()
header = do
    let initLines = """
      #include <runtime.h>
      /* \{ generatedString "RefC" } */

      """
    let headerFiles = Prelude.toList !(get HeaderFiles)
    fns <- get FunctionDefinitions
    update OutfileText $ appendL $
        [initLines] ++
        map (\h => "#include <\{h}>\n") headerFiles ++
        ["\n// function definitions"] ++
        fns ++
        ["\n// constant value definitions"] ++
        map (uncurry genConstant) (SortedMap.toList !(get ConstDef))
  where
    go : ConstDef -> String -> String -> String -> String
    go cdef ty tag v =
      "IDRIS2_UNUSED static Idris2_\{ty} const \{constantName cdef}"
        ++ " = { IDRIS2_STOCKVAL(\{tag}_TAG), \{v} };"
    genConstant : Constant -> ConstDef -> String
    genConstant c cdef = case c of
      I x   => go cdef "Int64" "INT64" (showIntMin x)
      I64 x => go cdef "Int64" "INT64" (showInt64Min x)
      B64 x => go cdef "Bits64" "BITS64" "UINT64_C(\{show x})"
      Db x  => go cdef "Double" "DOUBLE" (cDouble x)
      Str x => "IDRIS2_STRING_CONSTANT(\{constantName cdef}, \{cStringQuoted x});"
      BI _  => "IDRIS2_UNUSED static Idris2_Value *\{constantName cdef} = NULL;"
      _ => "/* bad constant */"





footer : {auto il : Ref IndentLevel Nat}
      -> {auto f : Ref OutfileText Output}
      -> {auto h : Ref HeaderFiles (SortedSet String)}
      -> Core ()
footer = do
    emit EmptyFC """

      // main function
      int main(int argc, char *argv[])
      {
          \{ ifThenElse (contains "idris_support.h" !(get HeaderFiles))
                        "idris2_setArgs(argc, argv);"
                        ""
          }
          // The main expression is run as the first green thread, so that
          // `fork` and `threadWait` behave the same everywhere.
          idris2_threadSchedulerRun(__mainExpression_0);
          return 0; // bye bye
      }
      """

-- Big programs are split in parts that a C compiler can compile in parallel
-- (one compile of the whole compiler takes minutes).  The file stays a single
-- file: the definitions are grouped in chunks of at least `minChunkSize`
-- bytes, and at most about `maxChunks` of them, each guarded by
--
--   #if !defined(IDRIS2_PARTS) || k * IDRIS2_PARTS / chunks == IDRIS2_PART
--
-- so compiling with -DIDRIS2_PARTS=p -DIDRIS2_PART=i (for i < p) builds the
-- i-th of p parts, and compiling without them builds the whole program.  The
-- prototypes and constants before the chunks are in every part.  Programs of
-- less than `minSplitSize` bytes are not split.
minSplitSize : Nat
minSplitSize = 4000000

minChunkSize : Nat
minChunkSize = 256000

maxChunks : Nat
maxChunks = 256

-- Group sized definitions in chunks of at least `target` bytes.
chunkDefs : (target : Nat) -> List (Nat, List String) -> List (List String)
chunkDefs target = go 0 [<]
  where
    go : Nat -> SnocList (List String) -> List (Nat, List String) -> List (List String)
    go _ [<] [] = []
    go _ acc [] = [concat (acc <>> [])]
    go n acc ((s, ls) :: rest)
      = let n' = n + s
            acc' = acc :< ls in
        if n' >= target
           then concat (acc' <>> []) :: go 0 [<] rest
           else go n' acc' rest

export
generateCSourceFileParts : {auto c : Ref Ctxt Defs}
                        -> {default [] additionalFFILangs : List String}
                        -> List (Name, ANFDef)
                        -> (outn : String)
                        -> Core Nat -- the number of chunks, 0 when not split
generateCSourceFileParts defs outn =
  do _ <- newRef ArgCounter 0
     _ <- newRef Foreigns $ fromList $ mapMaybe
            (\case (n, MkAForeign _ fargs _) => Just (cName n, length fargs)
                   _ => Nothing) defs
     _ <- newRef FunctionDefinitions []
     _ <- newRef ConstDef Data.SortedMap.empty
     _ <- newRef OutfileText DList.Nil
     _ <- newRef HeaderFiles empty
     _ <- newRef IndentLevel 0
     -- Each definition separately, so that a chunk never splits one (a CAF
     -- is a static function and the function that calls it).
     bodies <- traverse (\(n, d) =>
                 do put OutfileText DList.Nil
                    createCFunctions {additionalFFILangs} n d
                    ls <- reify <$> get OutfileText
                    pure (the Nat (foldl (\s, l => s + length l + 1) 0 ls), ls)) defs
     put OutfileText DList.Nil
     footer
     footerLines <- reify <$> get OutfileText
     put OutfileText DList.Nil
     header -- added after the definition traversal in order to add all encountered function defintions
     headerLines <- reify <$> get OutfileText

     let totalSize = the Nat (foldl (\s, b => s + fst b) 0 bodies)
     let chunks = if totalSize < minSplitSize
                     then []
                     else chunkDefs (max minChunkSize (totalSize `div` maxChunks + 1)) bodies
     let nchunks = length chunks
     let guarded = concat $ zipWith
           (\k, ls => "#if !defined(IDRIS2_PARTS) || \{show k} * IDRIS2_PARTS / \{show nchunks} == IDRIS2_PART"
                      :: ls ++ (if k + 1 == nchunks then footerLines else []) ++ ["#endif"])
           [0 .. pred nchunks] chunks
     let allLines = if nchunks == 0
                       then headerLines ++ concatMap snd bodies ++ footerLines
                       else headerLines ++ guarded
     let code = fastConcat (map (++ "\n") allLines)

     coreLift_ $ writeFile outn code
     log "compiler.refc" 10 $ "Generated C file " ++ outn ++ " in " ++ show nchunks ++ " chunks"
     pure nchunks

export
generateCSourceFile : {auto c : Ref Ctxt Defs}
                   -> {default [] additionalFFILangs : List String}
                   -> List (Name, ANFDef)
                   -> (outn : String)
                   -> Core ()
generateCSourceFile defs outn
  = ignore $ generateCSourceFileParts {additionalFFILangs} defs outn

export
compileExpr : UsePhase
           -> Ref Ctxt Defs
           -> Ref Syn SyntaxInfo
           -> (tmpDir : String)
           -> (outputDir : String)
           -> ClosedTerm
           -> (outfile : String)
           -> Core (Maybe String)
compileExpr ANF c s _ outputDir tm outfile =
  do let outn = outputDir </> outfile ++ ".c"
     let outobj = outputDir </> outfile ++ ".o"
     let outexec = outputDir </> outfile

     coreLift_ $ mkdirAll outputDir
     cdata <- getCompileData False ANF tm
     let defs = anf cdata

     chunks <- generateCSourceFileParts defs outn
     Just objs <- compileCObjectFiles chunks outn outobj
       | Nothing => pure Nothing
     compileCFiles objs outexec

compileExpr _ _ _ _ _ _ _ = pure Nothing



export
executeExpr : Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
              (execDir : String) -> ClosedTerm -> Core ()
executeExpr c s tmpDir tm = do
  do let outfile = "_tmp_refc"
     Just _ <- compileExpr ANF c s tmpDir tmpDir tm outfile
       | Nothing => do coreLift_ $ putStrLn "Error: failed to compile"
     coreLift_ $ system (tmpDir </> outfile)

export
codegenRefC : Codegen
codegenRefC = MkCG (compileExpr ANF) executeExpr Nothing Nothing
