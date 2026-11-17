module Compiler.RefC.RefC

import Compiler.RefC.Borrow
import Compiler.RefC.CC
import Compiler.RefC.LocalClosures
import Compiler.RefC.Unbox

import Compiler.Common
import Compiler.CompileExpr
import Compiler.ANF
import Compiler.Generated

import Core.Directory

import Idris.Env
import Idris.Syntax

import Libraries.Data.DList
import Libraries.Data.NatSet
import Data.SortedSet
import Data.SortedMap
import Data.Bits
import Data.String
import Data.Vect

import System
import System.File
import System.Info

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

-- The names that begin with `idris2_` (in any case) are those of the support
-- library (`idris2_newValue`, `Idris2_Value`, `IDRIS2_MUSTTAIL`) and those that
-- the code generator makes besides the C names of the definitions (`cafName`,
-- `borrowName`, `idris2_constr_...`, `idris2_static_closure_...`, the
-- constants, and the local variables that are not numbered, like
-- `idris2_trmc_hole`): a C name of a definition that would begin with it
-- (that of a definition of the namespace `idris2`) is given another
-- beginning, `idris2_user_`, which they never have.  (The C name of a
-- definition has a `_` after its namespace, and the numbered local variables,
-- like `var_3`, a number after the only `_`: they never are the name of a
-- definition either.)
userCName : String -> String
userCName s
    = -- (most names are told apart by their first character)
      if (let c = substr 0 1 s in c == "i" || c == "I")
           && toLower (substr 0 7 s) == "idris2_"
         then "idris2_user_" ++ s
         else s

export
cName : Name -> String
cName (NS ns n) = userCName (cCleanString (showNSWithSep "_" ns) ++ "_" ++ cName n)
cName (UN n) = cUserName n
cName (MN n i) = cCleanString n ++ "_" ++ cCleanString (show i)
cName (PV n d) = "pat__" ++ cName n
cName (DN _ n) = cName n
cName (Nested i n) = "n__" ++ cCleanString (show i) ++ "_" ++ cName n
cName (CaseBlock x y) = "case__" ++ cCleanString (show x) ++ "_" ++ cCleanString (show y)
cName (WithBlock x y) = "with__" ++ cCleanString (show x) ++ "_" ++ cCleanString (show y)
cName (Resolved i) = "fn__" ++ cCleanString (show i)

||| The C name of the function that computes the value of a definition without
||| arguments (a CAF, see `createCFunctions`), whose C name is `cn`.
cafName : String -> String
cafName cn = "idris2_caf_" ++ cn

||| The C name of the variant of a foreign function that borrows its arguments
||| (see `createCFunctions`), whose C name is `cn`.
borrowName : String -> String
borrowName cn = "idris2_borrow_" ++ cn

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

||| What stands for the value of an expression that ended in a jump (a call
||| in tail position): nothing is done with it.
unreachable : String
unreachable = "NULL /* unreachable */"

data ArgCounter : Type where
data EnvTracker : Type where
data Foreigns : Type where
data BorrowSigs : Type where
data ValueFns : Type where
data UnboxedVars : Type where
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

||| The constants of a program, by value, for the definitions of the generated
||| code to share.  The name of a constant is made of its value (see
||| `stableName`), not of a counter, so that adding a constant does not
||| rename the others: that would change the text of every definition that
||| uses them, and with it the object files of the program that could be
||| reused (see Compiler.RefC.CC).
record ConstTable where
  constructor MkConstTable
  ||| The constants and their definitions.
  constByValue : SortedMap Constant ConstDef
  ||| The names in use, to tell apart constants that have the same name.
  constNames : SortedSet String
  ||| The names of the constants that the definition being compiled uses.
  constUses : SortedSet String
  ||| The definitions of the static values (see `StaticVal`), by name.
  staticDefs : SortedMap String String

emptyConsts : ConstTable
emptyConsts = MkConstTable empty empty empty empty

-- A 64 bit hash of a string (FNV-1a over its characters, then mixed so that
-- every bit is good to use).
hashString : String -> Bits64
hashString s = mix (foldl (\h, c => (h `xor` cast (ord c)) * 1099511628211)
                          14695981039346656037 (unpack s))
  where
    mix : Bits64 -> Bits64
    mix h0 = let h1 = (h0 `xor` (h0 `shiftR` 33)) * 18397679294719823053
                 h2 = (h1 `xor` (h1 `shiftR` 29)) * 14181476777654086739 in
                 h2 `xor` (h2 `shiftR` 32)

-- The hash as a name: 16 hexadecimal digits.
hashName : String -> String
hashName s = pack (go 16 (hashString s) [])
  where
    digit : Bits64 -> Char
    digit d = if d < 10 then chr (cast d + ord '0') else chr (cast d - 10 + ord 'a')
    go : Nat -> Bits64 -> List Char -> List Char
    go Z _ acc = acc
    go (S k) h acc = go k (h `shiftR` 4) (digit (h `mod` 16) :: acc)

-- A string as a part of the name of a constant, when it is short.
stableName : String -> String
stableName s = if length s <= 40 then cCleanString s else hashName s

||| A constant that is not yet in the table, with a name that depends on its
||| value only (unless another constant has the name, which `names` tells).
||| The name is added to the uses of the definition.
bookConstant : {auto _ : Ref ConstDef ConstTable}
            -> Constant -> (String -> ConstDef) -> (stable : String) -> Core ConstDef
bookConstant c mk stable
    = do tbl <- get ConstDef
         let cdef = fresh tbl.constNames 0
         put ConstDef ({ constByValue $= insert c cdef
                       , constNames $= insert (constantName cdef)
                       , constUses $= insert (constantName cdef) } tbl)
         pure cdef
  where
    fresh : SortedSet String -> Nat -> ConstDef
    fresh names k
        = let cdef = mk (if k == 0 then stable else stable ++ "_" ++ show k) in
              if contains (constantName cdef) names then fresh names (S k) else cdef

||| The constant is used by the definition being compiled.
useConstant : {auto _ : Ref ConstDef ConstTable} -> ConstDef -> Core ()
useConstant cdef = update ConstDef { constUses $= insert (constantName cdef) }

||| A value that is known when the program is compiled, and that is data of
||| the C program rather than a value allocated at run time: a closure without
||| arguments, a constructor whose fields are all static values, a constant.
||| Like the string constants, it is immortal (taking and releasing references
||| to it does nothing) and it is never updated in place.
record StaticVal where
  constructor MkStaticVal
  ||| The C expression of the value (a constant expression).
  expr : String
  ||| The names of the constants that it is made of (see `constUses`).
  names : List String
  ||| How deep static constructors are nested in it.  The definitions of
  ||| the constants are written in the order of their names, which begin with
  ||| the depth, so that a constructor comes after its fields.
  depth : Nat

||| The static value of a closure of the function `n` (by its C name) that
||| has no arguments yet, and takes `arity`.
staticClosure : {auto _ : Ref ConstDef ConstTable} -> String -> Nat -> Core StaticVal
staticClosure fn arity = do
    let name = "idris2_static_closure_\{fn}_\{show arity}"
    update ConstDef { staticDefs $= insert name "IDRIS2_STATIC_CLOSURE(\{name}, \{fn}, \{show arity});"
                    , constUses $= insert name }
    pure (MkStaticVal "((Idris2_Value *)&\{name})" [name] 0)

||| The static value of a constructor with the tag `tag` and the fields
||| `fields`.  Its name is made of its definition, like the names of the
||| other constants (see `ConstTable`).
staticConstructor : {auto _ : Ref ConstDef ConstTable} -> Int -> List StaticVal -> Core StaticVal
staticConstructor tag fields = do
    let depth = S (foldl max 0 (map depth fields))
    let init = "\{show (length fields)}, \{show tag}, \{concat $ intersperse ", " (map expr fields)}"
    tbl <- get ConstDef
    let prefx = "idris2_static_con\{if depth < 10 then "0" else ""}\{show depth}_\{hashName init}"
    let name = fresh tbl.staticDefs prefx init 0
    let names = name :: concatMap names fields
    put ConstDef ({ staticDefs $= insert name (text name init)
                  , constUses $= (\u => foldl (flip insert) u names) } tbl)
    pure (MkStaticVal "((Idris2_Value *)&\{name})" names depth)
  where
    text : String -> String -> String
    text name init = "IDRIS2_STATIC_CONSTRUCTOR(\{name}, \{init});"

    -- (two definitions with the same hash get different names)
    fresh : SortedMap String String -> String -> String -> Nat -> String
    fresh defs prefx init k
        = let name = if k == 0 then prefx else prefx ++ "_" ++ show k in
              case lookup name defs of
                   Nothing => name
                   Just t => if t == text name init then name else fresh defs prefx init (S k)

||| May the expression have a static value: is it made of constructors,
||| closures without arguments and constants only?
staticShape : ANF -> Bool
staticShape (ALet _ _ value body) = staticShape value && staticShape body
staticShape (ACon _ _ _ _ _) = True
staticShape (AUnderApp _ _ _ []) = True
staticShape (APrimVal _ _) = True
staticShape _ = False

||| What a cell that a constructor may take over is chosen by: its number of
||| fields, and whether the constructor is told apart by its name (which takes
||| a slot of its own, see idris2_newNamedConstructor), so that the cell has
||| the right size, with the directive `refc-size-reuse`; otherwise the name of
||| the constructor, as before.
ReuseKey : Type
ReuseKey = Either Name (Nat, Bool)

||| A cell that a constructor may take over (see `addReuseConstructor`): the
||| C variable that holds it (NULL at run time when the scrutinee was not
||| unique), the constructor that it was, and the variables of its fields.
record ReuseCell where
  constructor MkReuseCell
  cellVar : String
  cellCon : Name
  cellFields : List Int

ReuseMap = SortedMap ReuseKey ReuseCell
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
  ||| May a constructor take over a cell of another constructor of the same
  ||| size (see `ReuseKey`)?
  sizeReuse : Bool
  ||| The parameters that the functions borrow (see Compiler.RefC.Borrow), by
  ||| C name.
  sigs : Signatures
  ||| The variables that are alive during the whole call of the function
  ||| without being owned by it: its borrowed parameters, and the fields of
  ||| the borrowed values that a `case` looked at.  A borrowed variable is
  ||| never owned (a use that needs a reference takes one).
  borrowed : SortedSet AVar
  ||| The functions (C name, arity) that always return a value, never a call
  ||| left for the trampoline of the caller: their calls are not trampolined
  ||| (see `returnsValue`).
  valueFns : SortedMap String Nat
  ||| Is the function compiled with tail recursion modulo cons (see
  ||| `trmcFunction`): a value that it returns goes in the hole of the last
  ||| cell that it made, and the first cell is returned.
  trmc : Bool
  ||| The variables whose values are static (see `StaticVal`).
  statics : SortedMap Int StaticVal
  ||| May a constructor be a static value?  Not the cell that tail recursion
  ||| modulo cons makes with a hole, which is filled later.
  staticOK : Bool

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

-- The position of the code that a line comes from is a comment after the
-- line, in an element of the output of its own, that begins with a character
-- that tells where it goes: after the line (`sameLine`), or in a line after
-- it (`ownLine`).  It is a part of the single file, but not of the units that
-- a C compiler compiles (see `withComments` and `withoutComments`): the
-- positions change when the program is changed above the code, and the object
-- file does not.
sameLine : Char
sameLine = '\x01'

ownLine : Char
ownLine = '\x02'

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
        (Yes _) => flip appendR [indentedLine, strCons sameLine comment]
        (No _)  => flip appendR [indentedLine, strCons ownLine comment]

||| An element of the output that is not a part of the text: it tells that the
||| definition has a call in tail position that is a jump (IDRIS2_MUSTTAIL,
||| see `plainReturn`).
jumpMark : String
jumpMark = "\x03"

commentTag : String -> Maybe Char
commentTag s = if s /= "" && (first == sameLine || first == ownLine || s == jumpMark)
                  then Just first
                  else Nothing
  where
    first : Char
    first = assert_total (strIndex s 0)

||| The lines that `emit` made, with the comments about their code.
withComments : List String -> List String
withComments (l :: c :: rest)
    = if l == jumpMark then withComments (c :: rest)
      else if c == jumpMark then withComments (l :: rest)
      else case commentTag c of
           Just t => if t == sameLine
                        then (lJust l maxLineLengthForComment ' ' ++ " " ++ assert_total (strTail c))
                               :: withComments rest
                        else l :: (lJust "" maxLineLengthForComment ' ' ++ " " ++ assert_total (strTail c))
                               :: withComments rest
           Nothing => l :: withComments (c :: rest)
withComments ls = filter (/= jumpMark) ls

||| The declaration of a variable whose value is static (see `StaticVal`) is
||| written with the number of the variable in front, between two
||| `staticMark`s: `dropUnusedStatics` removes them, and the declarations of
||| the variables that the definition does not use.
staticMark : Char
staticMark = '\x04'

emitStatic : {auto oft : Ref OutfileText Output}
          -> {auto il : Ref IndentLevel Nat}
          -> Int -> String -> Core ()
emitStatic var line = do
    indent <- indentation
    update OutfileText (flip snoc (strCons staticMark (show var) ++ strCons staticMark (indent ++ line)))

||| The numbers of the variables `var_N` in a line.
varsOfLine : List Char -> SortedSet Int -> SortedSet Int
varsOfLine ('v' :: 'a' :: 'r' :: '_' :: rest) acc
    = let (ds, rest') = span isDigit rest in
          varsOfLine rest' (maybe acc (\n => insert n acc) (parseInteger {a = Int} (pack ds)))
varsOfLine (_ :: rest) acc = varsOfLine rest acc
varsOfLine [] acc = acc

||| Remove the marks of the declarations of static values in the definition
||| being written (see `staticMark`), and those that declare a variable
||| that is not used.
dropUnusedStatics : {auto oft : Ref OutfileText Output} -> Core ()
dropUnusedStatics = do
    ls <- reify <$> get OutfileText
    when (any marked ls) $ do
      let used : SortedSet Int
               = foldl (\acc, l => if marked l then acc else varsOfLine (unpack l) acc) SortedSet.empty ls
      put OutfileText (appendR DList.Nil (mapMaybe (unmark used) ls))
  where
    marked : String -> Bool
    marked l = l /= "" && assert_total (strIndex l 0) == staticMark

    unmark : SortedSet Int -> String -> Maybe String
    unmark used l
        = if marked l
             then let (n, rest) = break (== staticMark) (assert_total (strTail l)) in
                      if maybe False (`contains` used) (parseInteger {a = Int} n)
                         then Just (assert_total (strTail rest))
                         else Nothing
             else Just l

||| Tell that the definition being written has a jump (see `jumpMark`).
markJump : {auto oft : Ref OutfileText Output} -> Core ()
markJump = update OutfileText (flip snoc jumpMark)

||| The `return` of a value that is not the result of a jump.  In a function
||| that has jumps too, GCC checks them by walking back from every `return`
||| through all the paths that reach it, until a statement that reads or
||| writes memory: with many branches in a row that only compute, that takes
||| time exponential in their number (minutes for a unit of the compiler,
||| with GCC 16).  IDRIS2_PLAIN_RETURN stops the walk at once (see runtime.h).
plainReturn : {auto oft : Ref OutfileText Output}
           -> {auto il : Ref IndentLevel Nat}
           -> String -> Core ()
plainReturn value = do
    ls <- reify <$> get OutfileText
    emit EmptyFC $ if any (== jumpMark) ls
                      then "IDRIS2_PLAIN_RETURN return \{value};"
                      else "return \{value};"

||| The lines that `emit` made, without the comments about their code.
withoutComments : List String -> List String
withoutComments = filter (isNothing . commentTag)

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
removeVars = applyFunctionToVars "idris2_removeReference" . filter (/= "NULL")

dupVars : {auto oft : Ref OutfileText Output}
           -> {auto il : Ref IndentLevel Nat}
           -> List String
           -> Core ()
dupVars = applyFunctionToVars "idris2_newReference" . filter (/= "NULL")


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

||| Is the value of the variable static (see `StaticVal`)?  Such a variable
||| is never owned, and no reference is taken where it is used: its value
||| is immortal.
isStaticIn : Env -> AVar -> Bool
isStaticIn env (ALocal i) = isJust (lookup i env.statics)
isStaticIn _ ANull = False

avarToC : Env -> AVar -> String
avarToC env ANull = "NULL"
avarToC env var =
    if isStaticIn env var then varName var
    else if isUnboxedIn env.unboxed var then boxInt var
    else if contains var env.owned then varName var
        -- case when the variable is borrowed
    else "idris2_newReference(" ++ varName var ++ ")"

avarsToC : Env -> Owned -> List AVar -> List String
avarsToC _ _ [] = []
avarsToC env owned (ANull :: vars) = "NULL" :: avarsToC env owned vars
avarsToC env owned (v::vars) =
  let v' = varName v in
      if isStaticIn env v
          then v' :: avarsToC env owned vars
      else if isUnboxedIn env.unboxed v
          then boxInt v :: avarsToC env owned vars
      else if contains v owned
          then v'::avarsToC env (delete v owned) vars
          else "idris2_newReference(\{v'})"::avarsToC env owned vars -- when v is borrowed

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

||| The C arguments of a call of a function with the signature `sig` (see
||| Compiler.RefC.Borrow): the arguments of the borrowed parameters are passed
||| as they are, the others as `avarsToC` passes them.  The variables passed
||| borrowed must be neither owned nor C integers (see `borrowedCall`).
sigArgsToC : Env -> Owned -> List (AVar, Bool) -> List String
sigArgsToC _ _ [] = []
sigArgsToC env owned ((ANull, _) :: rest) = "NULL" :: sigArgsToC env owned rest
sigArgsToC env owned ((v, True) :: rest) = varName v :: sigArgsToC env owned rest
sigArgsToC env owned ((v, False) :: rest)
    = if isStaticIn env v then varName v :: sigArgsToC env owned rest
      else if isUnboxedIn env.unboxed v then boxInt v :: sigArgsToC env owned rest
      else if contains v owned then varName v :: sigArgsToC env (delete v owned) rest
      else "idris2_newReference(\{varName v})" :: sigArgsToC env owned rest

||| Can the call be made in tail position, i.e. are no variables that we own
||| (or C integers, which are passed as new values) passed to borrowed
||| parameters?  They would have to be released after the call.  The borrow
||| analysis makes such parameters owned.
tailBorrowsOK : Env -> List (AVar, Bool) -> Bool
tailBorrowsOK env
    = all (\(v, b) => not b || not (contains v env.owned || isUnboxedIn env.unboxed v))

||| The arguments of a call, paired with whether the parameters are borrowed.
withSignature : Env -> Name -> List AVar -> (Bool, List (AVar, Bool))
withSignature env n args
    = case signatureOf env.sigs (cName n) (length args) of
           Just sig => (True, zip args sig)
           Nothing => (False, map (\a => (a, False)) args)

||| The result of a call (not in tail position) of the function `fn` with
||| `nargs` arguments: through the trampoline, but for the functions that
||| always return a value.
trampolined : Env -> String -> Nat -> String -> String
trampolined env fn nargs call
    = if lookup fn env.valueFns == Just nargs
         then call
         else "idris2_trampoline(\{call})"

||| A call (not in tail position) of a function that borrows some of its
||| parameters (see Compiler.RefC.Borrow).  The variables that we own and pass
||| to borrowed parameters are released after the call: they are not given
||| to the owned parameters too (the function could release them before it
||| is done with the borrowed ones), these get new references.  A C integer
||| passed borrowed is made a value for the call.
borrowedCall : {auto a : Ref ArgCounter Nat}
            -> {auto oft : Ref OutfileText Output}
            -> {auto il : Ref IndentLevel Nat}
            -> FC -> Env -> String -> List (AVar, Bool) -> Core String
borrowedCall fc env fn pairs = do
    let passedBorrowed = fromList (map fst (filter snd pairs))
    let released = intersection env.owned passedBorrowed
    (args, boxes) <- cArgs (difference env.owned passedBorrowed) pairs
    let call = trampolined env fn (length pairs) "\{fn}(\{concat $ intersperse ", " args})"
    let drops = map varName (Prelude.toList released) ++ boxes
    if null drops
       then pure call
       else do
         r <- ("callVar_" ++) <$> getNextCounter
         emit fc "Idris2_Value *\{r} = \{call};"
         removeVars drops
         pure r
  where
    cArgs : Owned -> List (AVar, Bool) -> Core (List String, List String)
    cArgs _ [] = pure ([], [])
    cArgs owned ((ANull, _) :: rest) = mapFst ("NULL" ::) <$> cArgs owned rest
    cArgs owned ((v, True) :: rest)
        = if isUnboxedIn env.unboxed v
             then do
               t <- ("boxVar_" ++) <$> getNextCounter
               emit fc "Idris2_Value *\{t} = \{boxInt v};"
               (as, bs) <- cArgs owned rest
               pure (t :: as, t :: bs)
             else do
               (as, bs) <- cArgs owned rest
               pure (varName v :: as, bs)
    cArgs owned ((v, False) :: rest)
        = if isStaticIn env v
             then mapFst (varName v ::) <$> cArgs owned rest
          else if isUnboxedIn env.unboxed v
             then mapFst (boxInt v ::) <$> cArgs owned rest
             else if contains v owned
                then mapFst (varName v ::) <$> cArgs (delete v owned) rest
                else mapFst ("idris2_newReference(\{varName v})" ::) <$> cArgs owned rest

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
    let (borrows, pairs) = withSignature env n args
    if borrows && not (tailBorrowsOK env pairs)
       then do
         -- (the borrow analysis does not let this happen)
         emit fc "/* the call of \{cName n} below is not a tail call */"
         borrowedCall fc env (cName n) pairs
       else case env.self of
         Just (self, params) =>
           if self == cName n && length params == length args
              then selfTailCall env params (map snd pairs)
              else otherCall env pairs
         Nothing => otherCall env pairs
  where
    pendingCallVar : Core String
    pendingCallVar = do
      let pc = "pending_\{!(getNextCounter)}"
      emit fc "Idris2_PendingTailCall *\{pc} = &idris2_pendingTailCall;"
      pure pc

    -- (the worker, which holds the pending call, is found once: nothing in
    -- between can switch threads)
    pendingCall : List (AVar, Bool) -> Core String
    pendingCall pairs = do
      env <- get EnvTracker
      pc <- pendingCallVar
      emit fc "\{pc}->f = (void *)\{cName n};"
      emit fc "\{pc}->arity = \{show $ length args};"
      for_ (zip [0 .. length args] (sigArgsToC env env.owned pairs)) $ \(k, a) =>
        emit EmptyFC "\{pc}->args[\{show k}] = \{a};"
      pure "IDRIS2_TAILCALL"

    -- With GCC 15 or later, a call in tail position is a jump (musttail),
    -- which does not need the trampoline.  It is only possible when the
    -- callee does not take more arguments than the caller (they would not fit
    -- in the space of the arguments of the caller on the stack, depending on
    -- the ABI).  Other compilers use a pending tail call.
    otherCall : Env -> List (AVar, Bool) -> Core String
    otherCall env pairs =
      if length args <= env.selfArity || length args <= 8
         then do
           let args' = sigArgsToC env env.owned pairs
           -- (a callee that takes more arguments than the caller can still
           -- be jumped to when it takes all of them in registers, which
           -- depends on the platform: see IDRIS2_MUSTTAIL_REG_ARGS)
           emit EmptyFC $ if length args <= env.selfArity
                        then "#ifdef IDRIS2_MUSTTAIL"
                        else "#if defined(IDRIS2_MUSTTAIL) && IDRIS2_MUSTTAIL_REG_ARGS >= \{show (length args)}"
           markJump
           emit fc "IDRIS2_MUSTTAIL return \{cName n}(\{concat $ intersperse ", " args'});"
           emit EmptyFC "#else"
           pc <- pendingCallVar
           emit EmptyFC "\{pc}->f = (void *)\{cName n};"
           emit EmptyFC "\{pc}->arity = \{show $ length args};"
           for_ (zip [0 .. length args] args') $ \(k, a) =>
             emit EmptyFC "\{pc}->args[\{show k}] = \{a};"
           emit EmptyFC "return IDRIS2_TAILCALL;"
           emit EmptyFC "#endif"
           pure unreachable
         else pendingCall pairs

    -- A call of the function to itself: the arguments become the new values
    -- of the parameters, and the function starts again.  They are computed
    -- first, as they may refer to the parameters.  The parameters that are C
    -- integers get the integers of their arguments (see
    -- Compiler.RefC.Unbox): the arguments that we own, and that are not
    -- passed as values too, are released.
    -- (`borrowed` says which parameters are borrowed: their new values are
    -- borrowed too)
    selfTailCall : Env -> List Int -> List Bool -> Core String
    selfTailCall env params borrowed = do
      let pairs = zip params args
      let bparams = fromList (map fst (filter snd (zip params borrowed)))
      let ints = filter (\(p, _) => contains p env.unboxed) pairs
      let values = filter (\(p, _) => not (contains p env.unboxed)) pairs
      let vals = sigArgsToC env env.owned
                   (map (\(p, a) => (a, contains p bparams)) values)
      -- (a parameter that keeps its value is left alone)
      tmps <- traverse (\(p, v) => if v == "var_\{show p}"
                                      then pure Nothing
                                      else Just <$> getNewVarThatWillNotBeFreedAtEndOfBlock)
                       (zip (map fst values) vals)
      for_ (zip tmps vals) $ \(t, v) =>
        whenJust t $ \t => emit fc "Idris2_Value *\{t} = \{v};"
      itmps <- traverse (\(p, a) =>
                 if intOperand env a == intVarName p
                    then pure Nothing
                    else do
                      t <- getNewVarThatWillNotBeFreedAtEndOfBlock
                      emit fc "int64_t \{t} = \{intOperand env a};"
                      pure (Just t)) ints
      let passed = SortedSet.fromList (map snd values)
      let released = filter (\v => contains v env.owned && not (contains v passed))
                            (nub (map snd ints))
      removeVars (map varName released)
      for_ (zip (map fst values) tmps) $ \(p, t) =>
        whenJust t $ \t => emit fc "var_\{show p} = \{t};"
      for_ (zip (map fst ints) itmps) $ \(p, t) =>
        whenJust t $ \t => emit fc "\{intVarName p} = \{t};"
      -- A loop may run for long: let the other threads of the worker run
      -- if the scheduler asks for it.
      emit fc "IDRIS2_SAFEPOINT();"
      emit fc "goto idris2_self_entry;"
      pure unreachable


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
-- Increasing this number will worsen stack consumption and increase the codesize of idris2_dispatch.
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
    -- The values of the small types are never boxed (see `alwaysUnboxed`).
    B8 _  => "idris2_vp_to_Bits8(\{v})"
    B16 _ => "idris2_vp_to_Bits16(\{v})"
    I8 _  => "idris2_vp_to_Int8(\{v})"
    I16 _ => "idris2_vp_to_Int16(\{v})"
    B32 _ => "idris2_extractUInt64(\{v})"
    Ch _  => "idris2_extractUInt64(\{v})"
    B64 _ => "(uint64_t)idris2_extractUInt64(\{v})"
    _     => "idris2_extractInt64(\{v})"

||| The types whose values are never allocated, on any platform: they are
||| kept in the pointer itself (see _datatypes.h).
alwaysUnboxed : Constant -> Bool
alwaysUnboxed (B8 _) = True
alwaysUnboxed (B16 _) = True
alwaysUnboxed (I8 _) = True
alwaysUnboxed (I16 _) = True
alwaysUnboxed _ = False

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
    markJump
    emit fc "IDRIS2_TAIL_APPLY return \{call};"
    pure unreachable

||| The key of the cells that the constructor `n`, with the tag `tag` and
||| `nargs` fields, may take over (see `ReuseKey`).
reuseKey : Env -> Name -> Maybe Int -> Nat -> ReuseKey
reuseKey env n tag nargs
    = if env.sizeReuse then Right (nargs, isNothing (conTag tag)) else Left n

||| Is the variable the one that was loaded from field `k` of a cell whose
||| fields were loaded in the variables `fieldVars`?  (A variable is bound
||| once.)
sameField : List Int -> Nat -> AVar -> Bool
sameField fieldVars k (ALocal i) = getAt k fieldVars == Just i
sameField _ _ ANull = False

||| Does the constructor allocate a cell?  (The others are NULL or immortal
||| values of the runtime, see `ACon`.)
allocates : ConInfo -> Nat -> Bool
allocates ci nargs
    = nargs > 0 && not (ci == NIL || ci == NOTHING || ci == ZERO || ci == UNIT)

||| The keys of the cells that the constructors built by an expression may
||| take over.
usedReuseKeys : Env -> ANF -> SortedSet ReuseKey
usedReuseKeys env anf
    = fromList [ reuseKey env n tag k
               | (n, ci, tag, k) <- constructorsBuilt anf, allocates ci k ]

||| The function takes as arguments the current ReuseMap and the constructors that will be used.
||| Returns constructor variables to remove and constructors to reuse.
dropUnusedReuseCons : ReuseMap -> SortedSet ReuseKey -> (List String, ReuseMap)
dropUnusedReuseCons reuseMap usedCons =
    -- if no constructor will take the cell over, then the cell is released
    let dropReuseMap = differenceMap reuseMap usedCons in
    let actualReuseMap = intersectionMap reuseMap usedCons in
    (map cellVar (values dropReuseMap), actualReuseMap)

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
                    -> ReuseKey
                    -> Name
                    -> List Int
                    -> SortedSet ReuseKey
                    -> List String
                    -> ReuseMap
                    -> Core (List String, ReuseMap)
addReuseConstructor reuseMap sc key conName fieldVars consts shouldDrop actualReuseConsts =
    let conArgs = map (varName . ALocal) fieldVars in
    -- to avoid conflicts, we check that there is no cell of the same key in reuse map
    -- we also check that a constructor will take it over later and that the variable will be deleted
    -- (nullary constructors are not allocated, see `ACon`)
    if (isNothing $ SortedMap.lookup key reuseMap)
       && not (null conArgs)
       && contains key consts
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
        pure (shouldDrop \\ (sc :: conArgs), insert key (MkReuseCell constr conName fieldVars) actualReuseConsts)
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

||| Give the variable `var` the result of an expression, unless the
||| expression ended in a jump.
assignResult : {auto oft : Ref OutfileText Output}
            -> {auto il : Ref IndentLevel Nat}
            -> String -> String -> Core ()
assignResult var result
    = unless (result == unreachable) $ emit emptyFC "\{var} = \{result};"

mutual
    ||| The translation of an expression, as `r` says.
    cResult : {auto a : Ref ArgCounter Nat}
           -> {auto oft : Ref OutfileText Output}
           -> {auto il : Ref IndentLevel Nat}
           -> {auto e : Ref EnvTracker Env}
           -> {auto _ : Ref ConstDef ConstTable}
           -> ANF -> Result -> Core String
    cResult anf (AValue tailPosition) = cStatementsFromANF anf tailPosition
    cResult anf AnInt = cIntFromANF anf

    letGeneric : {auto a : Ref ArgCounter Nat}
              -> {auto oft : Ref OutfileText Output}
              -> {auto il : Ref IndentLevel Nat}
              -> {auto e : Ref EnvTracker Env}
              -> {auto _ : Ref ConstDef ConstTable}
              -> FC -> Int -> ANF -> ANF -> Result -> Core String
    letGeneric fc var value body r = do
        env <- get EnvTracker
        let usedVars = freeVariables body
        let borrowVal = intersection env.owned (delete (ALocal var) usedVars)
        let owned' = if contains (ALocal var) usedVars then insert (ALocal var) borrowVal else borrowVal
        let usedCons = usedReuseKeys env value
        -- When translating value into C, we borrow variables that will be used in body
        let valueEnv = { reuseMap $= (`intersectionMap` usedCons) } (moveFromOwnedToBorrowed env borrowVal)
        put EnvTracker valueEnv
        result <- cStatementsFromANF value NotInTailPosition
        -- (what `cStatementsFromANF` made of the value just above)
        sv <- staticOf valueEnv value
        let decl = "Idris2_Value * var_\{show var} = \{result};"
        case sv of
          -- A static value is not released, and its variable may not be
          -- used at all (when it only goes in a static constructor): see
          -- `dropUnusedStatics`.
          Just _ => emitStatic var decl
          Nothing => do
            emit fc decl
            unless (contains (ALocal var) usedVars) $ emit fc $ "idris2_removeReference(var_\{show var});"
        -- (a static value is not owned, see `isStaticIn`)
        put EnvTracker ({ owned := if isJust sv then borrowVal else owned'
                        , reuseMap $= (`differenceMap` usedCons)
                        , statics $= maybe id (insert var) sv } env)
        cResult body r

    ||| The static value of an expression, if it has one (see `StaticVal`).
    staticOf : {auto a : Ref ArgCounter Nat}
            -> {auto oft : Ref OutfileText Output}
            -> {auto il : Ref IndentLevel Nat}
            -> {auto e : Ref EnvTracker Env}
            -> {auto _ : Ref ConstDef ConstTable}
            -> Env -> ANF -> Core (Maybe StaticVal)
    staticOf env (AUnderApp _ n (S missing) [])
        = if env.staticOK then Just <$> staticClosure (cName n) (S missing)
                          else pure Nothing
    staticOf env anf@(ACon _ n ci tag args)
        = if ci == NIL || ci == NOTHING || ci == ZERO || ci == UNIT
             then pure $ Just (MkStaticVal "NULL" [] 0)
             else case (args, conTag tag) of
               ([], Just t) => pure $ if t < 256
                  then Just (MkStaticVal "idris2_nullaryConstructor(\{show t})" [] 0)
                  else Nothing
               (_, Just t) =>
                  if env.staticOK && length args <= 255
                     && isNothing (SortedMap.lookup (reuseKey env n tag (length args)) env.reuseMap)
                     then case the (Maybe (List StaticVal)) (traverse field args) of
                            Just fields =>
                              if all (\f => f.depth < 90) fields
                                 then Just <$> staticConstructor t fields
                                 else pure Nothing
                            Nothing => pure Nothing
                     else pure Nothing
               _ => pure Nothing
      where
        field : AVar -> Maybe StaticVal
        field (ALocal i) = lookup i env.statics
        field ANull = Just (MkStaticVal "NULL" [] 0)
    staticOf env anf@(APrimVal fc c) = case c of
        Str _ => do
          e <- cStatementsFromANF anf NotInTailPosition
          tbl <- get ConstDef
          pure $ map (\cdef => MkStaticVal e [constantName cdef] 0) (lookup c tbl.constByValue)
        -- (these are made by macros, which give constant expressions)
        Ch _ => small
        B8 _ => small
        B16 _ => small
        I8 _ => small
        I16 _ => small
        _ => pure Nothing
      where
        small : Core (Maybe StaticVal)
        small = pure $ Just (MkStaticVal !(cStatementsFromANF anf NotInTailPosition) [] 0)
    -- (the value of a `let` is often a chain of `let`s itself, which ends
    -- with the constructor that takes their variables.  The variables of
    -- such a chain are those of the `let`s that `cStatementsFromANF` wrote,
    -- with fewer cells to take over at most, so it found them static too.)
    staticOf env anf@(ALet _ var value body)
        = if staticShape anf
             then do sv <- staticOf env value
                     staticOf ({ statics $= maybe id (insert var) sv } env) body
             else pure Nothing
    staticOf _ _ = pure Nothing

    ||| A `let` of a variable that is a C integer (see Compiler.RefC.Unbox):
    ||| like `letGeneric`, but the variable is not a value that we own.
    letInt : {auto a : Ref ArgCounter Nat}
          -> {auto oft : Ref OutfileText Output}
          -> {auto il : Ref IndentLevel Nat}
          -> {auto e : Ref EnvTracker Env}
          -> {auto _ : Ref ConstDef ConstTable}
          -> FC -> Int -> ANF -> ANF -> Result -> Core String
    letInt fc var value body r = do
        env <- get EnvTracker
        let usedVars = freeVariables body
        let borrowVal = intersection env.owned (delete (ALocal var) usedVars)
        let usedCons = usedReuseKeys env value
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
               -> {auto _ : Ref ConstDef ConstTable}
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
    cIntFromANF (ACrash fc msg) = pure "(idris2_crashMsg(\{cStringQuoted msg}), 0)"
    cIntFromANF anf = throw $ InternalError "[refc] Not an Int expression: \{show anf}"

    concaseBody : {auto a : Ref ArgCounter Nat}
                 -> {auto e : Ref EnvTracker Env}
                 -> {auto oft : Ref OutfileText Output}
                 -> {auto il : Ref IndentLevel Nat}
                 -> {auto _ : Ref ConstDef ConstTable}
                 -> Env
                 -> String -> String -> List Int -> ANF -> Result
                 -> Core ()
    concaseBody env returnvar expr args body r = do
        increaseIndentation
        _ <- foldlC (\k, arg => do
            emit emptyFC "Idris2_Value *var_\{show arg} = ((Idris2_Constructor*)\{expr})->args[\{show k}];"
            pure (S k) ) 0 args

        let (shouldDrop, actualOwned) = dropUnusedOwnedVars env.owned (freeVariables body)
        let usedCons = usedReuseKeys env body
        let (dropReuseCons, actualReuseMap) = dropUnusedReuseCons env.reuseMap usedCons
        put EnvTracker ({owned := actualOwned, reuseMap := actualReuseMap} env)
        removeVars shouldDrop
        removeReuseConstructors dropReuseCons
        assignResult returnvar !(cResult body r)
        decreaseIndentation

    cStatementsFromANF : {auto a : Ref ArgCounter Nat}
                      -> {auto oft : Ref OutfileText Output}
                      -> {auto il : Ref IndentLevel Nat}
                      -> {auto e : Ref EnvTracker Env}
                      -> {auto _ : Ref ConstDef ConstTable}
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
                    case withSignature env n args of
                      (True, pairs) => borrowedCall fc env (cName n) pairs
                      _ => do
                        let args' = avarsToC env env.owned args
                        pure $ trampolined env (cName n) nargs "\{cName n}(\{concat $ intersperse ", " args'})"
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
            let call = "\{borrowName (cName n)}(\{concat $ intersperse ", " (map varName args)})"
            let owned = Prelude.toList $ intersection (fromList args) env.owned
            if null owned
               then pure call
               else do
                 let resultVar = "ffiVar_" ++ !(getNextCounter)
                 emit fc $ "Idris2_Value *" ++ resultVar ++ " = " ++ call ++ ";"
                 removeVars (map varName owned)
                 pure resultVar

    cStatementsFromANF anf@(AUnderApp fc n missing args) _ = do
        Just sv <- staticOf !(get EnvTracker) anf
          | Nothing => makeClosure fc n args missing
        pure sv.expr
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
    -- A cell made of a call of the function to itself, in a function
    -- compiled with tail recursion modulo cons (see `trmcFunction`).
    cStatementsFromANF anf@(ALet fc var value body) InTailPosition = do
        env <- get EnvTracker
        case (env.trmc, env.self) of
          (True, Just (self, params)) =>
            case (trmcPlan cName self (length params) anf, value) of
              (TrmcSite k, AAppName fc1 _ f as) =>
                let (borrows, pairs) = withSignature env f as in
                    if not borrows || tailBorrowsOK env pairs
                       then trmcSite env k fc1 f as
                       else plainLet env
              -- (the lets that compute the arguments, and those of values
              -- that only allocate, come first)
              (TrmcReorder anf', _) => cStatementsFromANF anf' InTailPosition
              _ => plainLet env
          _ => plainLet env
      where
        plainLet : Env -> Core String
        plainLet env = if contains var env.unboxed
                          then letInt fc var value body (AValue InTailPosition)
                          else letGeneric fc var value body (AValue InTailPosition)

        -- The cell is made first, with NULL in the field of the call, and
        -- goes in the hole of the previous cell; its field is the next hole.
        -- Then the call is a jump back to the start of the function, as for
        -- a call to itself in tail position (see `selfTailCall`).  The
        -- variables that the call takes are borrowed while the cell is
        -- made (the cell takes references to those that it holds too).
        trmcSite : Env -> Nat -> FC -> Name -> List AVar -> Core String
        trmcSite env k fc1 f as = do
            let keep = intersection env.owned (fromList as)
            put EnvTracker ({ staticOK := False } (moveFromOwnedToBorrowed env keep))
            let (fc2, cell') = case body of
                    ACon fc2 n ci tag cargs =>
                      (fc2, ACon fc2 n ci tag (map (\a => if a == ALocal var then ANull else a) cargs))
                    _ => (fc, body) -- (not a cell: see trmcDirect)
            cell <- cStatementsFromANF cell' NotInTailPosition
            c <- ("idris2_trmc_cell_" ++) <$> getNextCounter
            emit fc2 "Idris2_Value *\{c} = \{cell};"
            emit fc2 "*idris2_trmc_hole = \{c};"
            emit fc2 "idris2_trmc_hole = &((Idris2_Constructor *)\{c})->args[\{show k}];"
            env' <- get EnvTracker
            put EnvTracker ({ owned := keep, staticOK := env.staticOK } env')
            makeTailCall fc1 f as

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
        allocConstructor : Env -> Core String

        newConstructor : Core String
        newConstructor = do
                env <- get EnvTracker
                Just sv <- staticOf env (ACon fc n coninfo tag args)
                  | Nothing => allocConstructor env
                pure "\{sv.expr} /* \{show n} */"

        allocConstructor env = do
                let createNewConstructor = case conTag tag of
                      Just t => " = idris2_newConstructor(\{show (length args)}, \{show t});"
                      Nothing => " = idris2_newNamedConstructor(\{show (length args)}, idris2_constr_\{cName n});"

                emit fc " // constructor \{show n}"
                case SortedMap.lookup (reuseKey env n tag (length args)) $ reuseMap env of
                    Just cell => do
                        let constr = cellVar cell
                        -- The values of the fields, in the order in which
                        -- `fillArgs` would make them (a variable that is
                        -- used twice is taken over the first time).
                        let fields = zip3 [0 .. length args] args
                                          (avarsToC env env.owned args)
                        -- A field that gets the variable loaded from the
                        -- same field of the cell already holds it when the
                        -- cell is taken over: only the reference that the
                        -- variable does not give up (when it is used again)
                        -- is taken.
                        let inPlace : (Nat, AVar, String) -> Bool
                              = \(k, v, _) => env.sizeReuse && not (isUnboxedIn env.unboxed v)
                                                && sameField (cellFields cell) k v
                        let (kept, stored) = partition inPlace fields
                        emit fc "if (! \{constr}) {"
                        increaseIndentation
                        emit fc $ constr ++ createNewConstructor
                        for_ kept $ \(k, _, e) => emit EmptyFC "\{constr}->args[\{show k}] = \{e};"
                        decreaseIndentation
                        let dups = filter (\(_, v, e) => e /= varName v) kept
                        let retag = cellCon cell /= n
                        if null dups && not retag
                           then emit fc "}"
                           else do
                             emit EmptyFC "} else {"
                             increaseIndentation
                             for_ dups $ \(_, _, e) => emit EmptyFC "\{e};"
                             -- (a cell of another constructor of the same
                             -- size: the number of fields is the same)
                             when retag $ emit EmptyFC $ case conTag tag of
                               Just t => "\{constr}->tag = \{show t};"
                               Nothing => "\{constr}->args[\{show (length args)}] = (Idris2_Value *)idris2_constr_\{cName n};"
                             decreaseIndentation
                             emit fc "}"
                        for_ stored $ \(k, _, e) => emit EmptyFC "\{constr}->args[\{show k}] = \{e};"
                        pure "(Idris2_Value*)\{constr}"
                    Nothing => do
                        let constr = "constructor_\{!(getNextCounter)}"
                        emit fc $ "Idris2_Constructor* " ++ constr ++ createNewConstructor
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
        if tagSwitch
           then do
             -- (the constructors of the type all have tags: a `switch`)
             emit emptyFC "switch (((Idris2_Constructor *)\{sc'})->tag) {"
             for_ alts $ \alt@(MkAConAlt name _ tag _ _) => do
                 emit emptyFC "case \{show (fromMaybe 0 (conTag tag))}: { /* \{show name} */"
                 altBody env switchReturnVar alt
                 emit emptyFC "  break;"
                 emit emptyFC "}"
             whenJust mDef $ \body => do
                 emit emptyFC "default: {"
                 concaseBody env switchReturnVar "" [] body (AValue tailPosition)
                 emit emptyFC "}"
             emit emptyFC "}"
           else case (alts, mDef) of
             -- The only constructor of its type (a record, the dictionary
             -- of an interface): there is nothing to test.
             ([alt@(MkAConAlt name coninfo (Just _) _ _)], Nothing) =>
               if plain alt
                  then do
                    emit emptyFC "{ /* \{show name} */"
                    altBody env switchReturnVar alt
                    emit emptyFC "}"
                  else ifChain env switchReturnVar
             _ => ifChain env switchReturnVar
        pure switchReturnVar
      where
        erasedCon : ConInfo -> Bool
        erasedCon ci = ci == NIL || ci == NOTHING || ci == ZERO || ci == UNIT

        -- Is the constructor of the alternative told by its tag?
        plain : AConAlt -> Bool
        plain (MkAConAlt _ ci tag _ _)
            = not (erasedCon ci || ci == CONS || ci == JUST || ci == SUCC)
              && isJust (conTag tag)

        tagSwitch : Bool
        tagSwitch = all plain alts && length alts >= 2

        -- The body of an alternative, in the environment `env` of the case.
        altBody : Env -> String -> AConAlt -> Core ()
        altBody env switchReturnVar (MkAConAlt name coninfo tag args body) = do
            let sc' = varName sc
            let erased = erasedCon coninfo
            let conArgs = ALocal <$> args
            -- The fields of a borrowed value are borrowed (see
            -- Compiler.RefC.Borrow): it keeps them alive.  Those of a value
            -- that we hold are ours (we take references to them, or take
            -- them over when it is not used any more).
            let scBorrowed = contains sc env.borrowed
            let ownedWithArgs : Owned
                  = if scBorrowed then env.owned
                       else union (fromList conArgs) $ if erased then delete sc env.owned else env.owned
            let usedVars = freeVariables body
            let (shouldDrop, actualOwned) = dropUnusedOwnedVars ownedWithArgs usedVars
            let usedCons = usedReuseKeys env body
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
            (shouldDrop, actualReuseMap) <-
                the (Core (List String, ReuseMap)) $
                  if scBorrowed
                     then pure (shouldDrop, actualReuseMap)
                     else addReuseConstructor env.reuseMap sc' (reuseKey env name tag (length args)) name args usedCons shouldDrop actualReuseMap
            removeVars shouldDrop
            removeReuseConstructors dropReuseCons
            put EnvTracker ({ owned := actualOwned, reuseMap := actualReuseMap
                            , borrowed := if scBorrowed then SortedSet.union (fromList conArgs) env.borrowed
                                                         else env.borrowed } env)
            assignResult switchReturnVar !(cStatementsFromANF body tailPosition)
            decreaseIndentation

        ifChain : Env -> String -> Core ()
        ifChain env switchReturnVar = do
            let sc' = varName sc
            _ <- foldlC (\els, alt@(MkAConAlt name coninfo tag args body) => do
                if erasedCon coninfo then emit emptyFC "\{els}if (NULL == \{sc'} /* \{show name} \{show coninfo} */) {"
                    else if coninfo == CONS || coninfo == JUST || coninfo == SUCC
                    then emit emptyFC "\{els}if (NULL != \{sc'} /* \{show name} \{show coninfo} */) {"
                    else do
                        case conTag tag of
                            Nothing   => emit emptyFC "\{els}if (! strcmp(idris2_constructorName(\{sc'}), idris2_constr_\{cName name})) {"
                            Just tag' => emit emptyFC "\{els}if (((Idris2_Constructor *)\{sc'})->tag == \{show tag'} /* \{show name} */) {"
                altBody env switchReturnVar alt
                pure "} else ") "" alts
            case mDef of
                Nothing => pure ()
                Just body => do
                    emit emptyFC "} else {"
                    concaseBody env switchReturnVar "" [] body (AValue tailPosition)
            emit emptyFC "}"

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
             cdef <- case lookup c constdefs.constByValue of
                          Just cdef => do useConstant cdef
                                          pure cdef
                          Nothing => bookConstant c CDBI (stableName $ show x)
             pure "idris2_integerConstant(&\{constantName cdef}, \"\{show x}\")"
    cStatementsFromANF (APrimVal fc c) _ = do
      constdefs <- get ConstDef
      case lookup c constdefs.constByValue of
           Just cdef => do useConstant cdef
                           pure "((Idris2_Value*)&\{constantName cdef})" -- the constant already booked.
           Nothing => dyngen
     where
        orStagen : (String -> ConstDef) -> (stable : String) -> Core String
        orStagen mk stable = do -- booking the constant to generate later
            cdef <- bookConstant c mk stable
            pure "((Idris2_Value*)&\{constantName cdef})"
        dyngen : Core String
        dyngen = case c of
            I x => if x >= -2147483648 && x <= 2147483647
                then pure "idris2_mkInt64(INT64_C(\{show x}))" -- unboxed on 64 bit platforms
                else orStagen CDI64 $ cCleanString $ show x
            I8 x  => pure "idris2_mkInt8(INT8_C(\{show x}))"
            I16 x => pure "idris2_mkInt16(INT16_C(\{show x}))"
            I32 x => pure "idris2_mkInt32(INT32_C(\{show x}))"
            I64 x => if x >= -2147483648 && x <= 2147483647
                then pure "idris2_mkInt64(INT64_C(\{show x}))"
                else orStagen CDI64 $ cCleanString $ show x
            BI x => if x >= 0 && x < 100
                then pure "idris2_getPredefinedInteger(\{show x})"
                else pure "idris2_mkIntegerLiteral(\"\{show x}\")"
            B8 x  => pure "idris2_mkBits8(UINT8_C(\{show x}))"
            B16 x => pure "idris2_mkBits16(UINT16_C(\{show x}))"
            B32 x => pure "idris2_mkBits32(UINT32_C(\{show x}))"
            B64 x => if x >= 0 && x <= 4294967295
               then pure "idris2_mkBits64(UINT64_C(\{show x}))"
               else orStagen CDB64 $ show x
            Db x => orStagen CDDb $ cCleanString $ show x
            Ch x  => pure "idris2_mkChar(\{escapeChar x})"
            Str s => orStagen CDStr $ hashName s
            PrT t => pure $ cPrimType t
            WorldVal => pure "(NULL /* World */)"

    cStatementsFromANF (AErased fc) _ = pure "NULL"
    -- Like the Scheme backends: print the message and stop.
    cStatementsFromANF (ACrash fc msg) _ = pure "idris2_crashMsg(\{cStringQuoted msg})"

    ||| A `case` on constants, which gives a value or a C integer.  A
    ||| scrutinee that is a C integer is switched on as it is.
    constCase : {auto a : Ref ArgCounter Nat}
             -> {auto oft : Ref OutfileText Output}
             -> {auto il : Ref IndentLevel Nat}
             -> {auto e : Ref EnvTracker Env}
             -> {auto _ : Ref ConstDef ConstTable}
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
                  -- A value of a small type is never allocated: there is
                  -- no reference to release.
                  let env = if alwaysUnboxed c then { owned $= delete sc } env else env
                  for_ alts $ \(MkAConstAlt c' body) => do
                      emit emptyFC "case \{const2Integer c' 0}: {"
                      concaseBody env switchReturnVar "" [] body r
                      emit emptyFC "  break;"
                      emit emptyFC "}"
                  whenJust def $ \body => do
                      emit emptyFC "default: {"
                      concaseBody env switchReturnVar "" [] body r
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

||| The optimisations that a directive turns off, for measurements and to
||| find the culprit of a bug.  `--directive refc-size-reuse` turns on the
||| reuse of cells across constructors of the same size (see `ReuseKey`): it
||| is off by default, as the code it gives makes GCC very slow on some big
||| functions (more than an hour for a part of the C of the compiler, which
||| takes two minutes without it), for little gain (at most 1.4%).
record RefCOptions where
  constructor MkRefCOptions
  optSizeReuse : Bool
  ||| `--directive refc-no-trmc` (see `trmcFunction`)
  optTrmc : Bool
  ||| not `--directive refc-no-static` (see `StaticVal`)
  optStatics : Bool

||| The options of the directives (read once per program).
refcOptions : {auto c : Ref Ctxt Defs} -> Core RefCOptions
refcOptions = do
    ds <- getDirectives RefC
    pure $ MkRefCOptions ("refc-size-reuse" `elem` ds)
                         (not ("refc-no-trmc" `elem` ds))
                         (not ("refc-no-static" `elem` ds))

||| The variables of the function `n` (C name `cn`) that are C integers (see
||| Compiler.RefC.Unbox).
unboxedOf : {auto c : Ref Ctxt Defs}
         -> SortedMap String Nat -> Name -> String -> List Int -> ANF
         -> Core (SortedSet Int)
unboxedOf foreigns n cn args anf = do
    let nargs = length args
    let loops = nargs > 0 && nargs <= MaxExtractFunArgs
                && hasSelfTailCall cn nargs anf
    let calls = MkCalls (\m, as => loops && cName m == cn && length as == nargs)
                        (\m, as => lookup (cName m) foreigns == Just (length as))
    if hasIntOp anf
       then unboxedVars calls loops args <$> intParams n args <*> pure anf
       else pure empty

||| Does the function `cn` with the parameters `args` always return a value,
||| never a pending tail call or a closure that its arguments complete (see
||| runtime.h)?  So it is when no expression in tail position calls a
||| function (but a foreign one, or itself in a loop, see `selfTailCall`) or
||| applies a closure, whatever the C compiler (with or without musttail).  A
||| constant always gives a value (see idris2_constantValue).
||| Is the function with the C name `cn` and `nargs` parameters compiled with
||| tail recursion modulo cons?  So it is when it makes a cell of a call to
||| itself in tail position (`map f (x :: xs) = f x :: map f xs`, see
||| `trmcSiteShape`): rather than calling itself and then making the cell, it
||| makes the cell with a hole for the result of the call, and loops (the
||| cells are its own until it returns the first one, so they may be filled
||| in later); the stack does not grow with the list.  The other expressions
||| in tail position must give values (or be calls of the function to itself,
||| which are jumps): a call of another function there would not be a tail
||| call any more, as its result goes in the hole.
trmcFunction : (Name -> Nat -> Bool) -> String -> Nat -> ANF -> Bool
trmcFunction foreign cn nargs anf
    = nargs > 0 && nargs <= MaxExtractFunArgs && sites anf && ok anf
  where
    -- (a chain of lets is normalised once, see trmcNormalise)
    sites : ANF -> Bool
    sites a@(ALet _ _ _ _)
        = let n = trmcNormalise a in trmcChain cName cn nargs n || sites (chainEnd n)
    sites (AConCase _ _ alts def)
        = any (\(MkAConAlt _ _ _ _ b) => sites b) alts || maybe False sites def
    sites (AConstCase _ _ alts def)
        = any (\(MkAConstAlt _ b) => sites b) alts || maybe False sites def
    sites _ = False

    ok : ANF -> Bool
    ok a@(ALet _ _ _ _)
        = let n = trmcNormalise a in trmcChain cName cn nargs n || ok (chainEnd n)
    ok (AAppName _ _ f as)
        = foreign f (length as) || (cName f == cn && length as == nargs)
    ok (AApp _ _ _ _) = False
    ok (AUnderApp _ _ Z _) = False
    ok (AConCase _ _ alts def)
        = all (\(MkAConAlt _ _ _ _ b) => ok b) alts && maybe True ok def
    ok (AConstCase _ _ alts def)
        = all (\(MkAConstAlt _ b) => ok b) alts && maybe True ok def
    ok _ = True

returnsValue : (Name -> Nat -> Bool) -> String -> List Int -> ANF -> Bool
returnsValue foreign cn args anf
    = let nargs = length args
          loops = nargs > 0 && nargs <= MaxExtractFunArgs
                  && hasSelfTailCall cn nargs anf in
          nargs == 0 || go loops nargs anf
  where
    go : Bool -> Nat -> ANF -> Bool
    go loops nargs (AAppName _ _ n as)
        = foreign n (length as) || (loops && cName n == cn && length as == nargs)
    go _ _ (AApp _ _ _ _) = False
    go _ _ (AUnderApp _ _ Z _) = False -- (a closure that has all its arguments)
    go loops nargs (ALet _ _ _ body) = go loops nargs body
    go loops nargs (AConCase _ _ alts def)
        = all (\(MkAConAlt _ _ _ _ body) => go loops nargs body) alts
          && maybe True (go loops nargs) def
    go loops nargs (AConstCase _ _ alts def)
        = all (\(MkAConstAlt _ body) => go loops nargs body) alts
          && maybe True (go loops nargs) def
    go _ _ _ = True

||| The prototypes that the definition of `key` (its C name) needs the other
||| definitions to see: they go in the header of the single file, and in the
||| units that refer to `key`.
addProtos : {auto f : Ref FunctionDefinitions (SortedMap String (List String))}
         -> (key : String) -> List String -> Core ()
addProtos key ps = update FunctionDefinitions $ \m =>
                     insert key (ps ++ fromMaybe [] (lookup key m)) m

createCFunctions : {auto c : Ref Ctxt Defs}
                -> {auto fo : Ref Foreigns (SortedMap String Nat)}
                -> {auto vf : Ref ValueFns (SortedMap String Nat)}
                -> {auto bs : Ref BorrowSigs Signatures}
                -> {auto uv : Ref UnboxedVars (SortedMap String (SortedSet Int))}
                -> {auto a : Ref ArgCounter Nat}
                -> {auto _ : Ref ConstDef ConstTable}
                -> {auto f : Ref FunctionDefinitions (SortedMap String (List String))}
                -> {auto oft : Ref OutfileText Output}
                -> {auto il : Ref IndentLevel Nat}
                -> {auto h : Ref HeaderFiles (SortedSet String)}
                -> {default [] additionalFFILangs : List String}
                -> RefCOptions
                -> (n : Name)
                -> (canonN : Name) -- the same, with stable numbers (see `canonName`)
                -> ANFDef
                -> Core ()
createCFunctions opts n canonN (MkAFun args anf) = do
    let cn = cName canonN
    let nargs = length args
    let params = if nargs == 0 then "(void)"
               else if nargs > MaxExtractFunArgs then "(Idris2_Value *idris2_arglist[\{show nargs}])"
               else ("\n(\n" ++ (showSep "\n" $ addCommaToList (map (\i =>  "  Idris2_Value * var_" ++ (show i)) args))) ++ "\n)"
    let fn = "Idris2_Value *\{cn}" ++ params
    addProtos cn [fn ++ ";\n"]
    -- A definition without arguments (a constant) is evaluated once, the
    -- first time that it is needed, like the top level constants of the
    -- Scheme backends: its body is in a function of its own, and its value is
    -- kept for good (it is immortal).
    let body = if nargs == 0
                  then "static Idris2_Value *\{cafName cn}" ++ params
                  else fn

    -- The parameters that the function borrows (see Compiler.RefC.Borrow):
    -- the caller keeps them alive, so they are neither owned nor released.
    sigs <- get BorrowSigs
    let borrowedParams = maybe [] (\sig => map fst (filter snd (zip args sig)))
                               (signatureOf sigs cn nargs)
    let borrowedVars = fromList $ ALocal <$> borrowedParams
    let argsVars = fromList $ ALocal <$> args
    let bodyFreeVars = freeVariables anf
    let shouldDrop = difference argsVars (union bodyFreeVars borrowedVars)
    let argsNrs = getArgsNrList args Z
    emit EmptyFC body
    emit EmptyFC "{"
    increaseIndentation
    when (nargs > MaxExtractFunArgs) $ do
      _ <- foldlC (\i, j => do
         emit EmptyFC "Idris2_Value *var_\{show j} = idris2_arglist[\{show i}];"
         pure $ i + 1) 0 args
      pure ()
    foreigns <- get Foreigns
    let trmc = opts.optTrmc
               && trmcFunction (\m, k => lookup (cName m) foreigns == Just k) cn nargs anf
    -- (a function compiled with tail recursion modulo cons loops too)
    let loops = nargs > 0 && nargs <= MaxExtractFunArgs
                && (trmc || hasSelfTailCall cn nargs anf)
    -- The first cell that it makes, and where the next value goes.
    when trmc $ do
      emit EmptyFC "Idris2_Value *idris2_trmc_result = NULL;"
      emit EmptyFC "Idris2_Value **idris2_trmc_hole = &idris2_trmc_result;"
    -- The variables that are C integers (see Compiler.RefC.Unbox): the
    -- parameters among them are unboxed once, before the loop starts.
    unboxed <- case lookup cn !(get UnboxedVars) of
                 Just u => pure u
                 Nothing => unboxedOf foreigns n cn args anf
    let unboxedParams = filter (`contains` unboxed) args
    for_ unboxedParams $ \p => do
      emit EmptyFC "int64_t \{intVarName p} = idris2_vp_to_Int64(var_\{show p});"
      unless (p `elem` borrowedParams) $
        emit EmptyFC "idris2_removeReference(var_\{show p});"
    when loops $ emit EmptyFC "idris2_self_entry: ;"
    removeVars (varName <$> Prelude.toList shouldDrop)
    _ <- newRef EnvTracker (MkEnv ((bodyFreeVars `difference` fromList (ALocal <$> unboxedParams))
                                     `difference` borrowedVars)
                              empty
                              (if loops then Just (cn, args) else Nothing)
                              -- (many arguments are passed in an array)
                              (if nargs > MaxExtractFunArgs then 1 else nargs)
                              foreigns unboxed opts.optSizeReuse sigs borrowedVars
                              !(get ValueFns) trmc empty opts.optStatics)
    if trmc
       then do
         assignResult "*idris2_trmc_hole" !(cStatementsFromANF anf InTailPosition)
         plainReturn "idris2_trmc_result"
       else do
         result <- cStatementsFromANF anf InTailPosition
         -- (nothing to return after a jump)
         unless (result == unreachable) $ plainReturn result
    decreaseIndentation
    emit EmptyFC  "}\n"
    dropUnusedStatics
    -- (idris2_constantValue makes it once, even with threads running in
    -- parallel.)
    when (nargs == 0) $ do
      emit EmptyFC fn
      emit EmptyFC "{"
      emit EmptyFC "  static Idris2_Constant constant;"
      emit EmptyFC "  return idris2_constantValue(&constant, \{cafName cn});"
      emit EmptyFC "}\n"
    emit EmptyFC  ""
    pure ()


createCFunctions _ n canonN (MkACon tag arity nt) =
  case conTag tag of
    Nothing => do
      let n' = cName canonN
      -- extern: in a generated file compiled in parts (see
      -- generateCSourceFile) the definition is in one part only.
      addProtos n' ["extern char const idris2_constr_\{n'}[];"]
      emit EmptyFC "char const idris2_constr_\{n'}[] = \{cStringQuoted $ show n};"
    Just _ =>
      emit EmptyFC $ ( "// \{show n} Constructor tag " ++ show tag ++ " arity " ++ show arity) -- Nothing to compile here


createCFunctions _ n canonN (MkAForeign ccs fargs ret) = do
  case parseCC (additionalFFILangs ++ ["RefC", "C"]) ccs of
      Just (lang, fctForeignName :: extLibOpts) => do
          let cLang = if lang == "RefC"
                         then CLangRefC
                         else CLangC
          let isStandardFFI = elem lang $ the (List String) ["RefC", "C"]
          let fctName = if isStandardFFI
                           then UN $ Basic $ fctForeignName
                           else NS (mkNamespace lang) canonN
          if isStandardFFI
             then case extLibOpts of
                      [lib, header] => update HeaderFiles $ insert header
                      _ => pure ()
             else emit EmptyFC $ additionalFFIStub fctName fargs ret
          let params = "(" ++ showSep ", " (replicate (length fargs) "Idris2_Value *") ++ ");"
          let fnDef = "Idris2_Value *" ++ cName canonN ++ params
          let borrowDef = "Idris2_Value *" ++ borrowName (cName canonN) ++ params
          addProtos (cName canonN) [fnDef ++ "\n", borrowDef ++ "\n"]
          typeVarNameArgList <- createFFIArgList fargs
          let argNames = (\(_, varName, _) => varName) <$> typeVarNameArgList

          -- The wrapper, which takes the arguments over (as the other
          -- functions do), for closures and partial applications
          emitFDef (cName canonN) typeVarNameArgList
          emit EmptyFC "{"
          increaseIndentation
          emit EmptyFC $ "Idris2_Value *retVal = " ++ borrowName (cName canonN) ++ "(" ++ showSep ", " argNames ++ ");"
          removeVars argNames
          emit EmptyFC "return retVal;"
          decreaseIndentation
          emit EmptyFC "}"

          -- The variant that borrows the arguments, for full applications
          -- (see `foreignCall`)
          emitFDef (borrowName (cName canonN)) typeVarNameArgList
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
      _ => throw $ InternalError "[refc] FFI not found for \{cName canonN}"
          -- not really total but this way this internal error does not contaminate everything else

-- A name without a definition to compile (a hole, for instance): like in the
-- Scheme backends, the program is compiled, and it stops with the message
-- when it gets to that name.
createCFunctions _ n canonN (MkAError (ACrash _ msg)) = do
    let fn = "Idris2_Value *\{cName canonN}(void)"
    addProtos (cName canonN) [fn ++ ";\n"]
    emit EmptyFC fn
    emit EmptyFC "{"
    increaseIndentation
    emit EmptyFC "return idris2_crashMsg(\{cStringQuoted msg});"
    decreaseIndentation
    emit EmptyFC "}"
createCFunctions _ n canonN (MkAError exp) = throw $ InternalError "[refc] Error with expression: \{show exp}"
-- not really total but this way this internal error does not contaminate everything else


||| The definition of a constant.
genConstant : Constant -> ConstDef -> String
genConstant c cdef = case c of
    I x   => go "Int64" "INT64" (showIntMin x)
    I64 x => go "Int64" "INT64" (showInt64Min x)
    B64 x => go "Bits64" "BITS64" "UINT64_C(\{show x})"
    Db x  => go "Double" "DOUBLE" (cDouble x)
    Str x => "IDRIS2_STRING_CONSTANT(\{constantName cdef}, \{cStringQuoted x});"
    BI _  => "IDRIS2_UNUSED static Idris2_Value *\{constantName cdef} = NULL;"
    _ => "/* bad constant */"
  where
    go : String -> String -> String -> String
    go ty tag v =
      "IDRIS2_UNUSED static Idris2_\{ty} const \{constantName cdef}"
        ++ " = { IDRIS2_STOCKVAL(\{tag}_TAG), \{v} };"

||| The definitions of the constants, by name.
constantTexts : ConstTable -> SortedMap String String
constantTexts tbl = mergeLeft tbl.staticDefs $
                    fromList $ map (\(c, cdef) => (constantName cdef, genConstant c cdef))
                                   (SortedMap.toList tbl.constByValue)

||| The beginning of every C file: the runtime and the headers of the foreign
||| functions.
preamble : (headerFiles : List String) -> List String
preamble headerFiles
    = ["#include <runtime.h>\n/* \{ generatedString "RefC" } */\n"]
      ++ map (\h => "#include <\{h}>\n") headerFiles

||| The prototypes of the definitions and the constants that a file uses.
declarations : (protos : List String) -> (constants : List String) -> List String
declarations protos constants
    = ["\n// function definitions\n"] ++ protos
      ++ ["\n// constant value definitions\n"] ++ constants

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

-- Big programs are split in units that a C compiler can compile in parallel
-- (one compile of the whole compiler takes minutes), and whose object files
-- can be reused when the program is compiled again after a small change.
--
-- The program is written twice:
--
-- * as a single file, which is what the bootstrap compiles (see
--   bootstrap-stage1-refc.sh) and what compiles by itself, without any
--   `-D`: the prototypes and constants of the whole program, then the
--   definitions of each unit `k` (of `n`, in order) guarded by
--
--     #if !defined(IDRIS2_PARTS) || k * IDRIS2_PARTS / n == IDRIS2_PART
--
--   so that compiling with -DIDRIS2_PARTS=p -DIDRIS2_PART=i (for i < p)
--   builds the i-th of p parts of it;
--
-- * as the unit files that `compileExpr` compiles (see Compiler.RefC.CC):
--   each has the definitions of its unit with only the prototypes and
--   constants that they use.  What the C compiler gets is thus the unit and
--   what it refers to, and the object file of a unit is made again only when
--   that changes.
--
-- What changes the text of a unit is meant to be only what is changed in the
-- program, and what it refers to: for that, the definitions are put in units
-- by the module they are in (and by a hash of their name, for big modules),
-- not by how big the definitions before them are; the number of units
-- depends only on the size of the program (and is a power of two, so that it
-- changes rarely); the names of the constants are made of their values; the
-- names of the local variables of a function (`tmp_17`) are numbered from 0
-- in each function; the numbers in the names that the elaborator makes (case
-- blocks, nested functions) are made stable (see `canonName`); and the
-- positions in the source of the code, which are comments, are not in the
-- units (see `emit`).  Programs of less than `minSplitSize` bytes are not
-- split.
minSplitSize : Nat
minSplitSize = 4000000

minChunkSize : Nat
minChunkSize = 256000

maxChunks : Nat
maxChunks = maxUnits

||| A compiled definition, with what is needed to put it in a unit.
record DefOut where
  constructor MkDefOut
  defSize : Nat
  defLines : List String
  ||| The module of the definition (its namespace), to put the definitions of
  ||| a module together.
  defModule : String
  ||| The C name of the definition.
  defName : String
  ||| The C names of the definitions that it refers to, and itself, whose
  ||| prototypes it needs.
  defRefs : List String
  ||| The names of the constants that it uses.
  defConsts : List String

moduleOf : Name -> String
moduleOf (NS ns _) = showNSWithSep "." ns
moduleOf (DN _ n) = moduleOf n
moduleOf (PV n _) = moduleOf n
moduleOf (Nested _ n) = moduleOf n
moduleOf _ = ""

||| The C names of the definitions that an expression refers to (that is, whose
||| prototypes the code of the expression needs), added to `acc`.
anfRefs : ANF -> SortedSet String -> SortedSet String
anfRefs (AAppName _ _ n _) acc = insert (cName n) acc
anfRefs (AUnderApp _ n _ _) acc = insert (cName n) acc
anfRefs (ALet _ _ v b) acc = anfRefs v (anfRefs b acc)
anfRefs (ACon _ n _ _ _) acc = insert (cName n) acc
anfRefs (AExtPrim _ _ p _) acc = insert (cName p) acc
anfRefs (AConCase _ _ alts def) acc
    = foldl (\a, (MkAConAlt n _ _ _ b) => anfRefs b (insert (cName n) a))
            (maybe acc (\d => anfRefs d acc) def) alts
anfRefs (AConstCase _ _ alts def) acc
    = foldl (\a, (MkAConstAlt _ b) => anfRefs b a)
            (maybe acc (\d => anfRefs d acc) def) alts
anfRefs _ acc = acc

------------------------------------------------------------------------
-- Names with numbers that do not change
--
-- The elaborator gives the functions that it makes inside another one (nested
-- functions, case blocks, with blocks, and the machine names made from them)
-- numbers: `Nested (outer, i)` has the index `outer` of the function in the
-- context (which means nothing in another module, and changes when a
-- definition is added before it) and a counter `i` of the module, which
-- changes when something is added above it in its module.  C names that have
-- them change when unrelated parts of the program do, and with them the
-- units that refer to them.  So these names are made again before the code
-- is generated: `outer` is left out, and `i` is replaced by its rank among
-- the numbers of the names of the same namespace that are alike (the nested
-- functions that have the same name, the case blocks of the same function):
-- they are still different, and change only when one of them is added or
-- removed.  The counters are those of modules, and two modules can have the
-- same namespace (the module A.B, and a `namespace B` in the module A): two
-- nested functions of the namespace can have the same `i`, and differ only by
-- `outer`.  So the numbers are ranked by `i`, then by `outer`, which tells
-- them apart (and gives the same ranks as `i` alone when no two have the same
-- `i`).

||| A group of numbers: the kind of name, its namespace, and what makes names
||| alike (the name of a nested function, the root of a case block).
NumKey : Type
NumKey = (String, String, String)

||| "outer:index:name", what a machine name made from a nested name begins
||| with: the outer index, the index and the name.
splitNested : String -> Maybe (Int, Int, String)
splitNested s
    = case break (== ':') (unpack s) of
           (a@(_ :: _), ':' :: r1) =>
              if all isDigit a
                 then case break (== ':') r1 of
                           (b@(_ :: _), ':' :: r2) =>
                              if all isDigit b
                                 then Just (cast (pack a), cast (pack b), pack r2)
                                 else Nothing
                           _ => Nothing
                 else Nothing
           _ => Nothing

||| "case block in outer (index)" (or "with block"), what lambda lifting makes
||| of the name of a case block (or with block): the kind ("C" or "W"), the
||| outer function and the index.
splitBlock : String -> Maybe (String, String, Int)
splitBlock s
    = let cs = unpack s in
          if isPrefixOf (unpack "case block in ") cs then parts "C" (List.drop 14 cs)
          else if isPrefixOf (unpack "with block in ") cs then parts "W" (List.drop 14 cs)
          else Nothing
  where
    parts : String -> List Char -> Maybe (String, String, Int)
    parts k body
        = case reverse body of
               (')' :: r1) => case span isDigit r1 of
                                   (ds@(_ :: _), '(' :: ' ' :: r2) =>
                                      Just (k, pack (reverse r2), cast (pack (reverse ds)))
                                   _ => Nothing
               _ => Nothing

||| The number of a name in its group: its index, then the outer index of a
||| nested name (see above).
NumOf : Type
NumOf = (Int, Int)

||| The numbers that a name has: their group, and the number.
nameNumbers : Namespace -> Name -> List (NumKey, NumOf)
nameNumbers ns (NS m n) = nameNumbers m n
nameNumbers ns (Nested (o, i) n) = (("N", showNSWithSep "." ns, show n), (i, o)) :: nameNumbers ns n
nameNumbers ns (CaseBlock s i) = [(("C", showNSWithSep "." ns, s), (i, 0))]
nameNumbers ns (WithBlock s i) = [(("W", showNSWithSep "." ns, s), (i, 0))]
nameNumbers ns (MN s _) = case splitNested s of
                               Just (o, i, rest) => [(("N", showNSWithSep "." ns, rest), (i, o))]
                               Nothing => case splitBlock s of
                                               Just (k, outer, i) => [((k, showNSWithSep "." ns, outer), (i, 0))]
                                               Nothing => []
nameNumbers ns (DN _ n) = nameNumbers ns n
nameNumbers ns (PV n _) = nameNumbers ns n
nameNumbers _ _ = []

||| The names in an expression, added to `acc`.
anfNames : ANF -> (Name -> a -> a) -> a -> a
anfNames (AAppName _ _ n _) f acc = f n acc
anfNames (AUnderApp _ n _ _) f acc = f n acc
anfNames (ALet _ _ v b) f acc = anfNames v f (anfNames b f acc)
anfNames (ACon _ n _ _ _) f acc = f n acc
anfNames (AExtPrim _ _ p _) f acc = f p acc
anfNames (AConCase _ _ alts def) f acc
    = foldl (\a, (MkAConAlt n _ _ _ b) => anfNames b f (f n a))
            (maybe acc (\d => anfNames d f acc) def) alts
anfNames (AConstCase _ _ alts def) f acc
    = foldl (\a, (MkAConstAlt _ b) => anfNames b f a)
            (maybe acc (\d => anfNames d f acc) def) alts
anfNames _ f acc = acc

||| The expression with the names changed.
mapANFNames : (Name -> Name) -> ANF -> ANF
mapANFNames f (AAppName fc l n args) = AAppName fc l (f n) args
mapANFNames f (AUnderApp fc n m args) = AUnderApp fc (f n) m args
mapANFNames f (ALet fc v a b) = ALet fc v (mapANFNames f a) (mapANFNames f b)
mapANFNames f (ACon fc n ci t args) = ACon fc (f n) ci t args
mapANFNames f (AExtPrim fc l p args) = AExtPrim fc l (f p) args
mapANFNames f (AConCase fc sc alts def)
    = AConCase fc sc (map (\(MkAConAlt n ci t as b) => MkAConAlt (f n) ci t as (mapANFNames f b)) alts)
                     (map (mapANFNames f) def)
mapANFNames f (AConstCase fc sc alts def)
    = AConstCase fc sc (map (\(MkAConstAlt c b) => MkAConstAlt c (mapANFNames f b)) alts)
                       (map (mapANFNames f) def)
mapANFNames _ a = a

||| The ranks of the numbers of every group.
Numbering : Type
Numbering = SortedMap NumKey (SortedMap NumOf Nat)

-- The ranks of the numbers, from the smallest.
numbered : List NumOf -> SortedMap NumOf Nat
numbered xs = snd (foldl (\(k, m), x => (S k, insert x k m)) (Z, empty) xs)

||| The numbers of the names of the definitions, by group.
numbering : List (Name, ANFDef) -> Numbering
numbering defs = map (\s => numbered (Prelude.toList s)) (foldl one empty defs)
  where
    add : Name -> SortedMap NumKey (SortedSet NumOf) -> SortedMap NumKey (SortedSet NumOf)
    add n acc = foldl (\m, (k, i) => insert k (insert i (fromMaybe empty (lookup k m))) m)
                      acc (nameNumbers emptyNS n)

    one : SortedMap NumKey (SortedSet NumOf) -> (Name, ANFDef) -> SortedMap NumKey (SortedSet NumOf)
    one acc (n, MkAFun _ anf) = anfNames anf add (add n acc)
    one acc (n, _) = add n acc

-- The rank of a number in its group (the number itself if it is not known).
rank : Numbering -> NumKey -> NumOf -> Int
rank nb k i = maybe (fst i) cast (lookup k nb >>= lookup i)

||| The name with its numbers made stable (see above).
canonName : Numbering -> Namespace -> Name -> Name
canonName nb ns (NS m n) = NS m (canonName nb m n)
canonName nb ns (Nested (o, i) n)
    = Nested (0, rank nb ("N", showNSWithSep "." ns, show n) (i, o)) (canonName nb ns n)
canonName nb ns (CaseBlock s i) = CaseBlock s (rank nb ("C", showNSWithSep "." ns, s) (i, 0))
canonName nb ns (WithBlock s i) = WithBlock s (rank nb ("W", showNSWithSep "." ns, s) (i, 0))
canonName nb ns (MN s k)
    = case splitNested s of
           Just (o, i, rest) => MN ("0:" ++ show (rank nb ("N", showNSWithSep "." ns, rest) (i, o)) ++ ":" ++ rest) k
           Nothing => case splitBlock s of
                           Just (kind, outer, i) =>
                              MN ((if kind == "C" then "case block in " else "with block in ") ++ outer
                                    ++ " (" ++ show (rank nb (kind, showNSWithSep "." ns, outer) (i, 0)) ++ ")") k
                           Nothing => MN s k
canonName nb ns (DN s n) = DN s (canonName nb ns n)
canonName nb ns (PV n k) = PV (canonName nb ns n) k
canonName _ _ n = n

||| The definitions, with the names in their expressions made stable.
canonDefs : Numbering -> List (Name, ANFDef) -> List (Name, ANFDef)
canonDefs nb = map (\(n, d) => (n, case d of
                                        MkAFun as anf => MkAFun as (mapANFNames (canonName nb emptyNS) anf)
                                        MkAError anf => MkAError (mapANFNames (canonName nb emptyNS) anf)
                                        _ => d))

-- The smallest power of two that is at least `k`.
pow2AtLeast : Nat -> Nat
pow2AtLeast k = go 1
  where
    go : Nat -> Nat
    go p = if p >= k then p else go (p * 2)

||| The number of units of a program of `bytes` bytes: a power of two, which
||| a program has to grow a lot to change, of at most `maxChunks`.
unitCount : (chunkSize : Nat) -> (bytes : Nat) -> Nat
unitCount chunkSize bytes = min maxChunks (pow2AtLeast (max 1 (bytes `div` chunkSize)))

||| The unit of every definition (of `n` units).  The definitions of a module
||| are in the same unit, a module that is bigger than a quarter of a unit
||| is cut in as many (a power of two) pieces by the hashes of the names of its
||| definitions, and a unit is chosen for the pieces by the hash of the
||| module.  (A bigger module gets more pieces only when it has grown
||| twice, and then half of its definitions stay where they were.)
groupUnits : (n : Nat) -> List DefOut -> SortedMap Nat (List DefOut)
groupUnits n defs
    -- (not in a `where`: it would be computed at every use)
    -- (nor with a type: a definition with a type is a function that is
    -- called at every use, even if it has no parameters)
    = let atom = max 1 (foldl (\s, d => s + d.defSize) 0 defs `div` n `div` 4)

          sizes = foldl (\m, d => insert d.defModule (d.defSize + fromMaybe 0 (lookup d.defModule m)) m)
                        (the (SortedMap String Nat) empty) defs

          pieces = map (\s => if s <= atom then the Nat 1 else pow2AtLeast (minus (s + atom) 1 `div` atom)) sizes

          unitOf : DefOut -> Nat
          unitOf d
              = let b = fromMaybe 1 (lookup d.defModule pieces)
                    piece = if b <= 1 then 0 else cast (hashString d.defName `mod` cast b)
                    h = hashString (d.defModule ++ "#" ++ show piece) in
                    cast (h `mod` cast n)

          place : SortedMap Nat (List DefOut) -> DefOut -> SortedMap Nat (List DefOut)
          place m d = let k = unitOf d in
                          insert k (d :: fromMaybe [] (lookup k m)) m in
          map reverse (foldl place empty defs)

||| Do the functions borrow parameters (see Compiler.RefC.Borrow)?  Not with
||| `--directive refc-no-borrow`, a kill switch for comparisons.
||| `--directive refc-no-direct-results` traverses the results of every call
||| (see `returnsValue`).
refcDirectResults : {auto c : Ref Ctxt Defs} -> Core Bool
refcDirectResults = pure $ not ("refc-no-direct-results" `elem` !(getDirectives RefC))

||| The size in bytes from which a program is split in units, instead of
||| `minSplitSize`: `--directive refc-split-size=N`, or the environment variable
||| `IDRIS2_REFC_SPLIT_SIZE` (to test the units with small programs).
refcSplitSize : {auto c : Ref Ctxt Defs} -> Core (Maybe Nat)
refcSplitSize
    = do ds <- getDirectives RefC
         env <- coreLift $ idrisGetEnv "IDRIS2_REFC_SPLIT_SIZE"
         pure $ case mapMaybe (\d => if Data.String.isPrefixOf "refc-split-size=" d
                                        then parsePositive {a = Nat} (substr 16 (length d) d)
                                        else Nothing) ds of
                     (n :: _) => Just n
                     [] => env >>= parsePositive {a = Nat}

refcBorrowing : {auto c : Ref Ctxt Defs} -> Core Bool
refcBorrowing = pure $ not ("refc-no-borrow" `elem` !(getDirectives RefC))

||| Write the C code of a program to `outn`.  A program that is big enough is
||| also written in units (see above), whose files are made ready to compile:
||| returns what `compileUnits` needs (in Compiler.RefC.CC), the units that
||| need the C compiler and their sizes.  Nothing otherwise.
export
generateCSourceFileParts : {auto c : Ref Ctxt Defs}
                        -> {default [] additionalFFILangs : List String}
                        -> List (Name, ANFDef)
                        -> (outn : String)
                        -> Core (Maybe (Units, List Nat, List (Nat, Nat)))
generateCSourceFileParts defs0 outn =
  do -- The closures that are only applied once are made there (see
     -- Compiler.RefC.LocalClosures), unless
     -- `--directive refc-no-local-closures`.
     local <- pure $ not ("refc-no-local-closures" `elem` !(getDirectives RefC))
     let defs1 : List (Name, ANFDef)
               = if local then map (\(n, d) => (n, applyLocalClosures d)) defs0
                          else defs0
     -- The numbers in the names that the elaborator made are made stable
     -- (see `canonName`): `canons` are the names of the definitions.
     let nb = numbering defs1
     let defs = canonDefs nb defs1
     canons <- traverse (\(n, _) => pure (canonName nb emptyNS !(getFullName n))) defs
     _ <- newRef ArgCounter 0
     _ <- newRef Foreigns $ fromList $ mapMaybe
            (\(cn, (_, d)) => case d of
                                   MkAForeign _ fargs _ => Just (cName cn, length fargs)
                                   _ => Nothing) (zip canons defs)
     -- The variables that are C integers, and the parameters that are
     -- borrowed, of every function (see Compiler.RefC.Unbox and
     -- Compiler.RefC.Borrow).
     foreigns <- get Foreigns
     let named = map (\(cn, (n, d)) => (cName cn, n, d)) (zip canons defs)
     unboxed <- fromList <$> traverse (\(cn, n, d) =>
                  case d of
                       MkAFun args anf => pure (cn, !(unboxedOf foreigns n cn args anf))
                       _ => pure (cn, empty)) named
     _ <- newRef UnboxedVars unboxed
     -- The functions whose calls need no trampoline (see `returnsValue`).
     direct <- refcDirectResults
     _ <- newRef ValueFns $
            if direct
               then fromList $ mapMaybe (\(cn, _, d) =>
                      case d of
                        MkAFun args anf =>
                          if returnsValue (\m, k => SortedMap.lookup (cName m) foreigns == Just k) cn args anf
                             then Just (cn, length args) else Nothing
                        _ => Nothing) named
               else empty
     -- The functions with tail recursion modulo cons (see `trmcFunction`),
     -- which the borrowing must know.
     opts <- refcOptions
     let trmcFns : SortedSet String
           = if opts.optTrmc
                then fromList $ mapMaybe (\(cn, _, d) =>
                       case d of
                         MkAFun args anf =>
                           if trmcFunction (\m, k => SortedMap.lookup (cName m) foreigns == Just k)
                                           cn (length args) anf
                              then Just cn else Nothing
                         _ => Nothing) named
                else empty
     borrowing <- refcBorrowing
     _ <- newRef BorrowSigs $
            if borrowing
               then inferBorrowing cName
                      (\f, k => SortedMap.lookup f foreigns == Just k)
                      (\f => fromMaybe empty (SortedMap.lookup f unboxed))
                      MaxExtractFunArgs
                      (`contains` trmcFns)
                      (map (\(cn, _, d) => (cn, d)) named)
               else empty
     _ <- newRef FunctionDefinitions Data.SortedMap.empty
     _ <- newRef ConstDef emptyConsts
     _ <- newRef OutfileText DList.Nil
     _ <- newRef HeaderFiles empty
     _ <- newRef IndentLevel 0
     -- Each definition separately, so that a unit never splits one (a CAF
     -- is a static function and the function that calls it).  The local
     -- variables are numbered in each definition, so that the code of a
     -- definition does not change with the definitions before it.
     bodies <- traverse (\((cn, n, d), canonN) =>
                 do put OutfileText DList.Nil
                    put ArgCounter 0
                    update ConstDef { constUses := empty }
                    createCFunctions {additionalFFILangs} opts n canonN d
                    ls <- reify <$> get OutfileText
                    tbl <- get ConstDef
                    let refs = case d of
                                 MkAFun _ anf => anfRefs anf (SortedSet.singleton cn)
                                 _ => SortedSet.singleton cn
                    pure (MkDefOut (the Nat (foldl (\s, l => s + length l + 1) 0 ls)) ls
                                   (moduleOf canonN) cn (Prelude.toList refs)
                                   (Prelude.toList tbl.constUses))) (zip named canons)
     put OutfileText DList.Nil
     footer
     footerLines <- reify <$> get OutfileText
     protos <- get FunctionDefinitions
     consts <- constantTexts <$> get ConstDef
     headerFiles <- Prelude.toList <$> get HeaderFiles
     let pre = preamble headerFiles
     -- added after the definition traversal in order to add all encountered
     -- function defintions and constants
     let headerLines = pre ++ declarations (concat (values protos)) (values consts)

     let totalSize = the Nat (foldl (\s, d => s + d.defSize) 0 bodies)
     split <- refcSplitSize
     let nunits = the Nat $ if totalSize < fromMaybe minSplitSize split || isWindows
                     then 0
                     else unitCount (maybe minChunkSize (\n => max 1 (n `div` 16)) split) totalSize
     let text : List String -> String
         text ls = fastConcat (map (++ "\n") ls)
     let base = if Data.String.isSuffixOf ".c" outn
                   then substr 0 (length outn `minus` 2) outn
                   else outn
     -- What the headers that are not those of the runtime are made of
     extra <- extraHeaderFiles base headerFiles
     writeHeaderDeps base extra
     if nunits == 0
        then do coreLift_ $ writeFile outn $ text (headerLines ++ concatMap (withComments . defLines) bodies ++ footerLines)
                log "compiler.refc" 10 $ "Generated C file " ++ outn
                pure Nothing
        else do
          units <- prepareUnits base extra
          let groups = groupUnits nunits bodies
          Right h <- coreLift $ openFile outn WriteTruncate
            | Left err => throw $ FileErr outn err
          Right () <- coreLift $ fPutStr h (text headerLines)
            | Left err => throw $ FileErr outn err
          -- The main function is in the unit 0.
          let mainRef = cName (MN "__mainExpression" 0)
          (present, todo) <- units' units protos consts pre footerLines mainRef nunits groups h
          coreLift_ $ closeFile h
          log "compiler.refc" 10 $
            "Generated C file " ++ outn ++ " in " ++ show (length present) ++ " units, "
            ++ show (length todo) ++ " to compile"
          pure (Just (units, present, todo))
  where
    -- Make the files of the units, and the guarded definitions of the
    -- single file.
    units' : Units
          -> SortedMap String (List String) -> SortedMap String String
          -> (pre : List String) -> (footerLines : List String) -> (mainRef : String)
          -> (nunits : Nat) -> SortedMap Nat (List DefOut) -> (h : File)
          -> Core (List Nat, List (Nat, Nat))
    units' units protos consts pre footerLines mainRef nunits groups h = go 0 [<] [<]
      where
        go : Nat -> SnocList Nat -> SnocList (Nat, Nat) -> Core (List Nat, List (Nat, Nat))
        go k present todo
          = if k >= nunits
               then pure (present <>> [], todo <>> [])
               else do
                 let ds = fromMaybe [] (lookup k groups)
                 let isMain = k == 0
                 if null ds && not isMain
                    then go (S k) present todo
                    else do
                      let defsLines = concatMap defLines ds
                      let ls = concatMap (withComments . defLines) ds ++ (if isMain then footerLines else [])
                      let refs = SortedSet.fromList $
                                   (if isMain then [mainRef] else []) ++ concatMap defRefs ds
                      let used = SortedSet.fromList $ concatMap defConsts ds
                      let protoLines : List String
                            = concatMap (\r => fromMaybe [] (lookup r protos)) (Prelude.toList refs)
                      let constLines : List String
                            = mapMaybe (\n => lookup n consts) (Prelude.toList used)
                      let codeLines : List String
                            = withoutComments defsLines ++ (if isMain then footerLines else [])
                      let unitLines : List String
                            = pre ++ declarations protoLines constLines ++ codeLines
                      let guarded = "#if !defined(IDRIS2_PARTS) || \{show k} * IDRIS2_PARTS / \{show nunits} == IDRIS2_PART"
                                    :: ls ++ ["#endif"]
                      Right () <- coreLift $ fPutStr h (fastConcat (map (++ "\n") guarded))
                        | Left err => throw $ FileErr "(the C file)" err
                      let unitText = fastConcat (map (++ "\n") unitLines)
                      needed <- updateUnit units k unitText
                      go (S k) (present :< k)
                         (if needed then todo :< (k, length unitText) else todo)

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

     plan <- generateCSourceFileParts defs outn
     Just objs <- the (Core (Maybe (List String))) $ case plan of
                       Nothing => do Just o <- compileCObjectFile outn outobj
                                       | Nothing => pure Nothing
                                     pure (Just (o :: []))
                       Just (units, present, todo) => compileUnits units present todo
       | Nothing => pure Nothing
     compileCFiles objs outexec

compileExpr _ _ _ _ _ _ _ = pure Nothing



export
executeExpr : Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
              (execDir : String) -> ClosedTerm -> Core ()
executeExpr c s tmpDir tm = do
  do let outfile = "_tmp_refc"
     Just _ <- compileExpr ANF c s tmpDir tmpDir tm outfile
       | Nothing => throw (UserError "failed to compile")
     coreLift_ $ system [tmpDir </> outfile]

export
codegenRefC : Codegen
codegenRefC = MkCG (compileExpr ANF) executeExpr Nothing Nothing
