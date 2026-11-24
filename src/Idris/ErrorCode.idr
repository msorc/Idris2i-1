||| The codes of the kinds of errors and warnings, and their explanations
||| (`idris2i-1 --explain E0101`, `:explain E0101` at the REPL).
|||
||| Each kind of error or warning that a user can meet has a code: `E` and
||| four digits for an error, `W` and four digits for a warning. The first two
||| digits are the area (`E01..` types and unification, `E04..` interface
||| resolution, ...); the registry below is in the order of the codes. A code
||| is never renumbered or given to another kind: a kind that goes away keeps
||| its entry, marked as no longer reported, and a new kind takes the next free
||| code of its area. Errors that are internal, or a message without a kind of
||| its own (`GenericMsg`), share `E0000`; warnings without a kind share
||| `W0000`. The reference page `docs/source/reference/error-codes.rst` is
||| printed from this registry (`idris2i-1 --list-error-codes`), and a test
||| checks that it is up to date.
module Idris.ErrorCode

import Core.Core
import Core.TT

import Data.List
import Data.String

%default covering

||| How to explain a kind of error: what it means, an example of the mistake,
||| and the usual fixes
public export
record Explanation where
  constructor MkExplanation
  summary : List String -- paragraphs
  example : List String -- lines of Idris code
  fixes : List String

public export
record ErrorKind where
  constructor MkErrorKind
  code : String
  title : String
  explanation : Maybe Explanation

||| The code of a warning
export
warningCode : Warning -> String

||| The code of an error. There is a clause for each constructor and no
||| catch-all, so that a new kind of error fails to compile (the module is
||| `%default covering`) until it is given a code; the only clauses that
||| match more than one case are within one constructor (`NotCovering`,
||| `TTCError`). An error that only gives the context of another
||| (where it was found, or the unification it happened in) has the code of
||| that other error.
export
errorCode : Error -> String
errorCode (Fatal err) = errorCode err
errorCode (CantConvert {}) = "E0101"
errorCode (CantSolveEq {}) = "E0102"
errorCode (PatternVariableUnifies {}) = "E0103"
errorCode (CyclicMeta {}) = "E0104"
errorCode (WhenUnifying _ _ _ _ _ _ _ err) = errorCode err
errorCode (ValidCase {}) = "E0603"
errorCode (UndefinedName {}) = "E0201"
errorCode (InvisibleName {}) = "E0202"
errorCode (BadTypeConType {}) = "E0207"
errorCode (BadDataConType {}) = "E0208"
errorCode (NotCovering _ _ (NonCoveringCall _)) = "E0602"
errorCode (NotCovering {}) = "E0601"
errorCode (NotTotal _ _ NotStrictlyPositive) = "E0701"
errorCode (NotTotal _ _ (BadCall _)) = "E0702"
errorCode (NotTotal _ _ (BadPath _ _)) = "E0703"
errorCode (NotTotal _ _ (RecPath _)) = "E0704"
errorCode (NotTotal _ _ (BadTypeCase _)) = "E0705"
errorCode ImpossibleCase = "E0000"
errorCode (LinearUsed {}) = "E0801"
errorCode (LinearMisuse {}) = "E0802"
errorCode (BorrowPartial {}) = "E0803"
errorCode (BorrowPartialType {}) = "E0804"
errorCode (AmbiguousName {}) = "E0203"
errorCode (AmbiguousElab {}) = "E0301"
errorCode (AmbiguousSearch {}) = "E0403"
errorCode (AmbiguityTooDeep {}) = "E0303"
errorCode (AllFailed {}) = "E0302"
errorCode (RecordTypeNeeded {}) = "E0901"
errorCode (DuplicatedRecordUpdatePath {}) = "E0902"
errorCode (NotRecordField {}) = "E0903"
errorCode (NotRecordType {}) = "E0904"
errorCode (IncompatibleFieldUpdate {}) = "E0905"
errorCode (InvalidArgs {}) = "E0309"
errorCode (TryWithImplicits {}) = "E0305"
errorCode (BadUnboundImplicit {}) = "E0306"
errorCode (CantSolveGoal {}) = "E0401"
errorCode (SearchNeeds {}) = "E0401"
errorCode (DeterminingArg {}) = "E0402"
errorCode (UnsolvedHoles {}) = "E0501"
errorCode (CantInferArgType {}) = "E0106"
errorCode (SolvedNamedHole {}) = "E0502"
errorCode (VisibilityError {}) = "E0204"
errorCode (NonLinearPattern {}) = "E0604"
errorCode (BadPattern {}) = "E0605"
errorCode (NoDeclaration {}) = "E0205"
errorCode (AlreadyDefined {}) = "E0206"
errorCode (NotFunctionType {}) = "E0105"
errorCode (RewriteNoChange {}) = "E1001"
errorCode (NotRewriteRule {}) = "E1002"
errorCode (CaseCompile {}) = "E0607"
errorCode (MatchTooSpecific {}) = "E0610"
errorCode (LiteralNotMatchable {}) = "E0608"
errorCode (BadDotPattern {}) = "E0606"
errorCode (BadImplicit {}) = "E0304"
errorCode (BadRunElab {}) = "E1003"
errorCode (RunElabFail err) = errorCode err
errorCode (GenericMsg {}) = "E0000"
errorCode (UniverseInconsistency {}) = "E0107"
errorCode (GenericMsgSol {}) = "E0000"
errorCode (GenericMsgTerm {}) = "E0000"
errorCode (OperatorBindingMismatch {}) = "E0308"
errorCode (TTCError (Format {})) = "E1203"
errorCode (TTCError _) = "E1204"
errorCode (FileErr {}) = "E1205"
errorCode (CantFindPackage {}) = "E1206"
errorCode (LazyImplicitFunction {}) = "E0307"
errorCode (LazyPatternVar {}) = "E0609"
errorCode (LitFail {}) = "E1103"
errorCode (LexFail {}) = "E1102"
errorCode (ParseFail {}) = "E1101"
errorCode (ModuleNotFound {}) = "E1201"
errorCode (CyclicImports {}) = "E1202"
errorCode ForceNeeded = "E0000"
errorCode (InternalError {}) = "E0000"
errorCode (UserError {}) = "E0000"
errorCode (NoForeignCC {}) = "E1301"
errorCode (BadMultiline {}) = "E1104"
errorCode (Timeout {}) = "E0001"
errorCode (FailingDidNotFail {}) = "E1401"
errorCode (FailingWrongError {}) = "E1402"
errorCode (InType _ _ err) = errorCode err
errorCode (InCon _ err) = errorCode err
errorCode (InLHS _ _ err) = errorCode err
errorCode (InRHS _ _ err) = errorCode err
errorCode (MaybeMisspelling err _) = errorCode err
errorCode (QuantitiesChosen _ _ _ err) = errorCode err
errorCode (WarningAsError wrn) = warningCode wrn

-- (a warning that reports an error has the code of the error)
warningCode (ParserWarning {}) = "W0001"
warningCode (UnreachableClause {}) = "W0002"
warningCode (ShadowingGlobalDefs {}) = "W0003"
warningCode (ShadowingLocalBindings {}) = "W0004"
warningCode (IncompatibleVisibility {}) = "W0005"
warningCode (Deprecated {}) = "W0006"
warningCode (WhereRecompute {}) = "W0007"
warningCode (UniverseIncomplete {}) = "W0008"
warningCode (UniverseUncheckedImports {}) = "W0009"
warningCode (GenericWarn {}) = "W0000"
warningCode (ErrorWarning err) = errorCode err

explained : String -> String -> List String -> List String -> List String -> ErrorKind
explained c t s e f = MkErrorKind c t (Just (MkExplanation s e f))

stub : String -> String -> ErrorKind
stub c t = MkErrorKind c t Nothing

||| Every code, in order
export
registry : List ErrorKind
registry =
  [ stub "E0000" "An error without a code of its own (an internal error, or a message from a library or an elaborator script)"
  , stub "E0001" "A time limit was reached"

  -- Types and unification
  , explained "E0101" "Type mismatch"
      [ "An expression has a type other than the one its context expects, or two types that must be the same are different. The message says which two types were compared, labelled `Expected:` (what the context needs) and `Got:` (what the expression has) when that is known, and then the part of them that differs (`Mismatch between: A and B.`)."
      , "When the two types only differ in a part that was inferred, the message says what was inferred and where (`This was postponed, and failed after inferring ...`)." ]
      [ "length : List a -> Nat"
      , ""
      , "f : List Int -> Int"
      , "f xs = length xs        -- length gives a Nat, f must return an Int" ]
      [ "Convert the value: `cast (length xs)` here."
      , "Fix the type of the definition, if it is the type that is wrong."
      , "Check the arguments: a missing or an extra argument makes the type of an application differ." ]
  , stub "E0102" "A constraint between two types was left unsolved"
  , explained "E0103" "A pattern variable stands for a value that is known"
      [ "In a pattern, a variable (or an implicit argument) must be free to match anything. When unification finds that it can only be one particular value, because of the type of another argument, the variable does not really bind anything new, and Idris2i-1 reports it."
      , "This often happens with implicit arguments that are named in the pattern, or when an argument's type forces another one." ]
      [ "data Vect : Nat -> Type -> Type where"
      , "  Nil  : Vect Z a"
      , "  (::) : a -> Vect k a -> Vect (S k) a"
      , ""
      , "f : Vect n a -> Nat"
      , "f {n = m} [] = m      -- m can only be Z here" ]
      [ "Write the value that the variable must have (`f {n = Z} [] = 0`), or leave the argument out of the pattern."
      , "Use a dot pattern (`.(Z)`) to say that the argument is forced by the others." ]
  , stub "E0104" "A metavariable would have to contain itself (a cyclic solution)"
  , stub "E0105" "A term that is not a function is applied to arguments"
  , stub "E0106" "The type of an argument can't be inferred"
  , explained "E0107" "Universe inconsistency"
      [ "Only with `--check-universes`. Each `Type` stands for a universe, and the universes must be ordered: `Type : Type` is not allowed, a type is in a universe above those of its parts, and the fields of a constructor are in a universe no bigger than that of their data type. The definitions checked so far need a universe to be strictly bigger than itself, through the chain of constraints that the message lists, with the place of each `Type` involved and the definition each constraint comes from. Without the check such a program can prove `Void` (Girard's paradox)."
      , "See the reference page on universe checking for what is checked." ]
      [ "data U : Type where"
      , "  MkU : Type -> U       -- a U holds a type of the universe of U"
      , ""
      , "u : U"
      , "u = MkU U               -- U itself is not in a smaller universe" ]
      [ "Read the cycle: one of its steps is usually a type stored in a data type (or interface) of its own universe, or a type used at itself."
      , "Make the data type a parameter of what it stores (`data U : Type -> Type`) instead of storing a `Type` in it."
      , "A definition is universe polymorphic only in the universes which evaluation can't produce; give a second copy of the definition if it is needed at two universes." ]

  -- Names
  , explained "E0201" "Undefined name"
      [ "A name is used that is not defined, or not defined in any module that is imported. The message suggests names that are spelt alike, and the modules in the build directory or in the packages in use that export a definition of that name." ]
      [ "main : IO ()"
      , "main = printLn (sort [3, 1, 2])     -- sort is in Data.List" ]
      [ "Import the module that defines it (`import Data.List`), or add the package that provides it to `depends` in the `.ipkg` file, or pass `-p` to `idris2i-1`."
      , "Fix the spelling."
      , "Define the name before it is used in a `mutual` block, or declare its type first." ]
  , explained "E0202" "A name exists, but is not in scope here"
      [ "The name is defined, but it can't be used here: it is private to the module or namespace that defines it, or it is in a module that is not imported explicitly (a module imported by an imported module is not visible unless it is imported with `import public`)." ]
      [ "-- in module A"
      , "secret : Nat"
      , "secret = 42"
      , ""
      , "-- in module B"
      , "import A"
      , "x : Nat"
      , "x = secret      -- secret is private to A" ]
      [ "Export the definition: `export` makes its type visible, `public export` its definition too."
      , "Import the module that defines it explicitly."
      , "Use a function that the module exports instead." ]
  , stub "E0203" "A name is ambiguous: several definitions of it are in scope"
  , explained "E0204" "A definition refers to a definition that is less visible"
      [ "A definition that is exported can only refer, in the parts that are exported, to definitions that are exported as well: a `public export` definition can't use a private or `export` one in its body, and the type of an `export` definition can't use a private one. Otherwise a module that imports it would see a name that it can't use." ]
      [ "data Secret = MkSecret"
      , ""
      , "public export"
      , "reveal : Secret     -- Secret is private"
      , "reveal = MkSecret" ]
      [ "Make the definition referred to visible enough (`export` or `public export`)."
      , "Make the definition that refers to it less visible."
      , "Export only the type (`export` instead of `public export`) if the body need not be visible." ]
  , stub "E0205" "A definition has no type declaration"
  , stub "E0206" "A name is already defined"
  , stub "E0207" "The return type of a type constructor is not a type"
  , stub "E0208" "A data constructor does not return the type it belongs to"

  -- Elaboration
  , explained "E0301" "Ambiguous elaboration"
      [ "An overloaded name (a name defined in several namespaces, or a literal or syntax with several meanings) has more than one meaning that type checks here, and nothing says which one is meant. The message lists the results." ]
      [ "namespace A"
      , "  export"
      , "  val : Nat"
      , "  val = 1"
      , ""
      , "namespace B"
      , "  export"
      , "  val : Nat"
      , "  val = 2"
      , ""
      , "x : Nat"
      , "x = val" ]
      [ "Qualify the name with its namespace (`A.val`)."
      , "Give the expected type (`the Nat val`) if the meanings have different types."
      , "Hide one of the definitions with `%hide`." ]
  , explained "E0302" "No meaning of an overloaded name works"
      [ "Every meaning of an overloaded name (a name defined in several namespaces, a list literal, a `do` block, ...) failed to type check. The message lists the error of each meaning, the one that got furthest first; meanings that fail in the same way at the same place are listed together under one excerpt." ]
      [ "import Data.Vect"
      , ""
      , "xs : Vect 2 Nat"
      , "xs = [1, 2, 3]     -- both List and Vect literals fail" ]
      [ "Read the first error of the list: it is the meaning that came closest."
      , "Qualify the name (`Vect.(::)`) or give the expected type to say which meaning you want, so that its error is reported alone."
      , "`--candidate-error-count 0` shows all the meanings when some are left out." ]
  , stub "E0303" "The maximum depth of nested ambiguous names was exceeded"
  , explained "E0304" "An implicit argument can't be bound here"
      [ "An implicit argument (`{x}`, `@{x}`) is given or bound where the function does not have one of that name, or in a form that is not allowed there." ]
      [ "f : Nat -> Nat"
      , "f {m} n = n       -- f has no implicit argument m" ]
      [ "Check the name of the implicit argument against the type of the function (`:t f` at the REPL)."
      , "Bind the argument in the type first (`f : {m : Nat} -> Nat -> Nat`)." ]
  , stub "E0305" "Implicit arguments must be bound explicitly"
  , stub "E0306" "A name can't be bound implicitly with this type"
  , stub "E0307" "Implicit lazy functions are not supported"
  , stub "E0308" "An operator is used with a fixity that does not match its declaration"
  , stub "E0309" "Named arguments that the function does not have"

  -- Interface resolution
  , explained "E0401" "Can't find an implementation"
      [ "An interface constraint (or an `auto` argument) could not be satisfied. The message says why, as far as it can be told:"
      , "* no implementation of the interface matches the type at all;"
      , "* an implementation matches, but needs another constraint that fails: the message names the implementation (by its type and where it is defined) and the chain of constraints down to the one that fails;"
      , "* the implementation that would match is not visible here;"
      , "* a local implementation (a constraint of the function, or an `auto` argument) is in scope, but for other types;"
      , "* the type is not known yet (it has a `?` in it), so no implementation can be chosen." ]
      [ "data Colour = Red | Green"
      , ""
      , "describe : Colour -> String"
      , "describe c = show c      -- there is no Show Colour" ]
      [ "Write the implementation (`Show Colour where show Red = \"Red\" ...`), or derive one where a deriving library is available."
      , "Import the module that defines the implementation."
      , "Add the missing constraint to the type of the function (`Show a => a -> String`) when it is about a type variable."
      , "Say what the type is (with a type annotation or `the`) when the message shows a `?` in the goal." ]
  , explained "E0402" "An implementation can't be chosen: an argument that determines it is not known"
      [ "Some arguments of an interface determine which implementation is used (all of them, unless the interface says otherwise with `|`). If one of them is still unknown when the search runs, no implementation can be chosen, even if there is only one. The message names the argument that could not be inferred." ]
      [ "interface Default a where"
      , "  def : a"
      , ""
      , "Default Nat where"
      , "  def = 0"
      , ""
      , "x : String"
      , "x = show def      -- the type of def is not known" ]
      [ "Give the type: `show (the Nat def)`, or a type annotation on a `let`."
      , "Pass the implementation explicitly with `@{...}`."
      , "For a numeric literal, the default (`Integer`) is only used when nothing else says what the type is." ]
  , explained "E0403" "Several implementations match"
      [ "More than one implementation (or local constraint) satisfies an interface constraint, and the search does not choose between them. The message lists them, by their types and where they are defined; named implementations are listed by name." ]
      [ "interface Describe a where"
      , "  describe : a -> String"
      , ""
      , "Describe Int where"
      , "  describe _ = \"Int\""
      , ""
      , "[other] Describe Int where"
      , "  describe _ = \"other\""
      , ""
      , "%hint"
      , "otherHint : Describe Int"
      , "otherHint = other"
      , ""
      , "f : Int -> String"
      , "f = describe" ]
      [ "Choose one explicitly: `describe @{other}`."
      , "Remove the `%hint`, or one of the implementations."
      , "Name an implementation (`[name] Describe Int where`) so that it is only used when asked for." ]

  -- Holes
  , explained "E0501" "Unsolved holes"
      [ "A definition still contains holes that unification could not fill: implicit arguments, or `_` that it could not infer. The message lists them with where they were introduced. (Holes written as `?name` are allowed, and do not cause this error.)" ]
      [ "f : List a -> Nat"
      , "f xs = length []     -- the type of the elements of [] is unknown" ]
      [ "Give the missing value or type explicitly (`length {a = Nat} []`, `the (List Nat) []`)."
      , "Bind the implicit argument in the type of the definition." ]
  , stub "E0502" "A named hole was solved by unification"

  -- Coverage and patterns
  , explained "E0601" "A definition is not covering: cases are missing"
      [ "A definition declared `covering` or `total` (or every definition, with `%default covering` or `%default total`) does not have a clause for every possible input. The message lists the missing cases, written as patterns that can be pasted as clauses." ]
      [ "%default total"
      , ""
      , "isZero : Nat -> Bool"
      , "isZero Z = True" ]
      [ "Add the missing clauses."
      , "Add a final clause with a variable or `_` that covers the rest."
      , "If a case is impossible, write it with `impossible` so that Idris2i-1 checks it." ]
  , explained "E0602" "A definition is not covering: it calls a function that is not"
      [ "A definition that must be covering calls a function that is not covering (or is only `partial`). The call is shown, and why the function called is not covering." ]
      [ "%default total"
      , ""
      , "partial"
      , "first : List a -> a"
      , "first (x :: _) = x"
      , ""
      , "f : List Nat -> Nat"
      , "f xs = first xs" ]
      [ "Make the function called covering (`first : List a -> Maybe a`, for example)."
      , "Mark the calling definition `partial` if it really is." ]
  , explained "E0603" "An impossible clause is possible"
      [ "A clause marked `impossible` type checks, so it is not impossible: there are values that match it. Or the clause fails to type check for another reason than a contradiction, which the message gives." ]
      [ "f : Nat -> Nat"
      , "f Z impossible     -- Z is a Nat" ]
      [ "Write a right hand side for the clause."
      , "Check the pattern: the impossible case is often a different pattern than the one written." ]
  , stub "E0604" "A pattern variable is used more than once in a pattern"
  , stub "E0605" "A pattern is not valid"
  , stub "E0606" "A dot pattern is not valid"
  , stub "E0607" "A case tree can't be built for the clauses"
  , explained "E0608" "A literal pattern has nothing to match on"
      [ "A string, numeric or character literal in a pattern, at a type other than a primitive one, stands for `fromString \"...\"`, `fromInteger 3`, ... of that type. The pattern can only be matched if that application reduces to a constructor applied to arguments. For some types it does not: a `ByteString` is built by a foreign function, and a type whose conversion is not `public export` does not reduce outside its module. Then there is nothing to compare the value with, and the clause (or the `case` alternative) is rejected."
      , "This used to be accepted, and the clause then matched every value." ]
      [ "import Data.ByteString"
      , ""
      , "route : ByteString -> String"
      , "route \"/\" = \"home\"        -- fromString \"/\" is not a constructor form"
      , "route _ = \"other\"" ]
      [ "Bind a variable and compare it with `==`: `route p = if p == \"/\" then \"home\" else \"other\"`."
      , "For a type of your own, match on its constructor (`MkName \"me\"`), or make its conversion `public export` so that it reduces in patterns." ]
  , stub "E0609" "A lazy function can't be defined by pattern matching"
  , stub "E0610" "A pattern is more specific than its type allows"

  -- Totality
  , explained "E0701" "Not total: a type is not strictly positive"
      [ "A data type refers to itself to the left of an arrow in the type of one of its constructors. Such a type allows non-terminating programs to be written without recursion, so it is not total." ]
      [ "data Bad = MkBad (Bad -> Nat)" ]
      [ "Change the representation so that the type only occurs to the right of arrows."
      , "Mark the type (and what uses it) `partial` if that is acceptable." ]
  , explained "E0702" "Not total: it calls a function that is not total"
      [ "A definition that must be total calls a function that is not. The message shows the call, and why the function called is not total." ]
      [ "covering"
      , "loop : Nat -> Nat"
      , "loop n = loop n"
      , ""
      , "total"
      , "f : Nat -> Nat"
      , "f n = loop n" ]
      [ "Make the function called total."
      , "Mark the calling definition `covering` or `partial`." ]
  , explained "E0703" "Not total: a function that is not total is reachable"
      [ "A definition that must be total calls, through a path of other functions, a function that is not total. The message shows the path." ]
      [ "covering"
      , "loop : Nat -> Nat"
      , "loop n = loop n"
      , ""
      , "g : Nat -> Nat"
      , "g = loop"
      , ""
      , "total"
      , "f : Nat -> Nat"
      , "f = g" ]
      [ "Make the function at the end of the path total."
      , "Mark the definitions on the path `covering` or `partial`." ]
  , explained "E0704" "Not total: possibly not terminating"
      [ "A definition calls itself (or a cycle of definitions calls round) with arguments that are not known to get smaller. The message shows the recursive call, and how each argument compares to the pattern it must be smaller than." ]
      [ "total"
      , "count : Nat -> Nat"
      , "count n = count (S n)" ]
      [ "Recurse on a structurally smaller argument (a variable bound inside a constructor pattern)."
      , "Use `assert_smaller` or `assert_total` where you know the call terminates but Idris2i-1 can't see it."
      , "Recurse on a separate argument that decreases (a fuel argument, `Nat`)." ]
  , explained "E0705" "Not total: a type is matched on"
      [ "A clause takes a type apart by pattern matching, and the type is neither `Type` nor small, so the match can't be checked to terminate." ]
      [ "total"
      , "f : (a : Type) -> Nat"
      , "f Nat = 0"
      , "f _ = 1" ]
      [ "Pass a value that describes the type (a data type of codes) instead of the type itself."
      , "Mark the definition `covering`." ]

  -- Linearity
  , explained "E0801" "A linear variable is used more or less than once"
      [ "A variable bound with multiplicity 1 must be used exactly once in the body of its definition. The message says how many times it is used." ]
      [ "dup : (1 x : a) -> (a, a)"
      , "dup x = (x, x)" ]
      [ "Use the variable exactly once, or pass it to a function that returns what is needed of it."
      , "Drop the multiplicity 1 from the binder, if the value need not be linear." ]
  , explained "E0802" "A variable is used with the wrong multiplicity"
      [ "A variable is used in a context that needs another multiplicity: an erased (0) variable is used at run time, or a linear (1) one is passed where it may be used many times." ]
      [ "f : (0 n : Nat) -> Nat"
      , "f n = n       -- n is erased, it can't be returned" ]
      [ "Bind the variable with the multiplicity it is used at (`(n : Nat)`)."
      , "Use it only in types or other erased positions." ]
  , stub "E0803" "A borrowed value is partially applied"
  , stub "E0804" "A borrowed value has a partially applied type"

  -- Records
  , stub "E0901" "The type of a record update can't be inferred"
  , stub "E0902" "A record update sets the same field twice"
  , explained "E0903" "A field is not part of the record"
      [ "A record update (`{ field := value } r`) or a projection (`r.field`) names a field that the record type does not have." ]
      [ "record Point where"
      , "  constructor MkPoint"
      , "  x, y : Double"
      , ""
      , "move : Point -> Point"
      , "move = { z := 0 }" ]
      [ "Check the spelling of the field, and the record type it is used on."
      , "Give the type of the record when it can't be inferred (`the Point`)." ]
  , stub "E0904" "A record update is applied to something that is not a record"
  , stub "E0905" "Field updates are not compatible with each other"

  -- Rewriting and elaborator reflection
  , stub "E1001" "A rewrite changes nothing in the goal"
  , stub "E1002" "The term used to rewrite is not an equality"
  , stub "E1003" "An elaborator script returned a bad result"

  -- Parsing
  , explained "E1101" "Parse error"
      [ "The source can't be parsed. The message says what was expected at the place shown; when several alternatives were tried, each is listed with its error." ]
      [ "f : Nat -> Nat"
      , "f x = (x + 1" ]
      [ "Look at the place shown and just before it: a missing bracket, a missing `=` or `->`, or a line that is not indented enough."
      , "Check the indentation of `where`, `do`, `let` and `case` blocks: their lines must start in the same column." ]
  , explained "E1102" "Lexical error"
      [ "The source contains characters that do not form a token: an unterminated string or character literal, a comment that is not closed, or a character that can't appear there." ]
      [ "greeting : String"
      , "greeting = \"hello" ]
      [ "Close the string, the character literal or the comment."
      , "Escape special characters in strings (`\\\"`, `\\\\`)." ]
  , stub "E1103" "A literate source file can't be parsed"
  , stub "E1104" "A multi-line string is not laid out correctly"

  -- Modules, files and packages
  , explained "E1201" "Module not found"
      [ "An imported module can't be found in the source directory, in the build directory or in any package in use." ]
      [ "import Data.Lists      -- the module is Data.List" ]
      [ "Fix the name of the module."
      , "Add the package that provides it to `depends` in the `.ipkg` file, or pass `-p <package>` to `idris2i-1`."
      , "Check `sourcedir` in the `.ipkg` file, and that the file is where its module name says (`Data/Foo.idr` for `Data.Foo`)." ]
  , explained "E1202" "Modules import each other in a cycle"
      [ "A module imports, directly or through other modules, itself. Modules are checked one after another, so their imports can't form a cycle. The message lists the modules of the cycle." ]
      [ "-- A.idr"
      , "module A"
      , "import B"
      , ""
      , "-- B.idr"
      , "module B"
      , "import A" ]
      [ "Move the definitions that both modules need into a third module that both import."
      , "Merge the modules, or use `mutual` blocks within one module." ]
  , explained "E1203" "A compiled module (TTC file) has a format of another version"
      [ "A `.ttc` file was written by another version of the compiler, which stores modules in another format. This happens after the compiler is upgraded, or when the build directory or an installed package was built by another compiler." ]
      []
      [ "Remove the build directory (`rm -r build`, or `idris2i-1 --clean <package>.ipkg`) and build again."
      , "Reinstall the packages in use with the current compiler."
      , "Check that the `idris2i-1` in the `PATH` is the one the packages were installed with (`idris2i-1 --version`, `idris2i-1 --paths`)." ]
  , stub "E1204" "A compiled module (TTC file) is corrupt"
  , stub "E1205" "A file can't be read or written"
  , stub "E1206" "A package can't be found"

  -- Back ends
  , stub "E1301" "No back end accepts a foreign specifier"

  -- Failing blocks
  , stub "E1401" "A failing block did not fail"
  , stub "E1402" "A failing block failed with another error"

  -- Warnings
  , stub "W0000" "A warning without a code of its own"
  , stub "W0001" "A warning from the parser"
  , explained "W0002" "Unreachable clause"
      [ "A clause can never be used: the clauses before it match everything it matches. It is probably a mistake in the order of the clauses, or in a pattern (a variable where a constructor was meant: a lower case name in a pattern is a new variable, not a reference to a definition)." ]
      [ "isRed : String -> Bool"
      , "isRed colour = False"
      , "isRed \"red\" = True" ]
      [ "Put the more specific clause first."
      , "Check the patterns of the earlier clauses: a variable matches everything."
      , "Remove the clause if it is not needed." ]
  , explained "W0003" "A name bound implicitly shadows a global definition"
      [ "In a type, a lower case name that is not bound is bound implicitly, as an argument of the definition. When a global definition of that name exists, this is often a mistake: the global definition was meant, but it is a new variable. The message lists the names and the definitions they shadow." ]
      [ "x : Nat"
      , "x = 3"
      , ""
      , "f : Vect x Int -> Int     -- x here is a new variable, not 3" ]
      [ "Rename the variable, or bind it explicitly (`{x : Nat} -> ...`) if a variable is meant."
      , "Qualify the global name (`Main.x`) if the global definition is meant." ]
  , explained "W0004" "A local binding shadows another"
      [ "A local variable (in a pattern, a `let`, a lambda) has the name of another one in scope, which is no longer accessible." ]
      [ "f : Nat -> Nat -> Nat"
      , "f x y = let x = y in x" ]
      [ "Rename one of the variables." ]
  , stub "W0005" "A forward declaration and its definition have different visibilities"
  , explained "W0006" "Deprecated definition"
      [ "A definition marked `%deprecate` is used. It will be removed in a later version; its documentation usually says what to use instead, and is printed with the warning." ]
      [ "import Data.SortedSet"
      , ""
      , "xs : List Nat"
      , "xs = SortedSet.toList (fromList [1])" ]
      [ "Use what the documentation of the definition suggests instead." ]
  , stub "W0007" "A local definition without arguments is recomputed at each use"
  , explained "W0008" "The universe checker could not check some definitions completely"
      [ "Only with `--check-universes`. The universe checker checks the elaborated definitions again. Some elaborated terms are not well typed as far as it can tell (the motive of a `rewrite`, for instance, is built without being checked), so it checks what it can of them, but can't claim that they are consistent, and does not make them universe polymorphic. The warning lists them; `--log universe:1` says what was not checked in each." ]
      []
      [ "Nothing needs to be done; the definitions are checked as far as possible." ]
  , explained "W0009" "Imported modules were built without the universe check"
      [ "Only with `--check-universes`. The universe constraints of a module are saved in its TTC file when it is built with the option. Modules built without it contribute no constraints, so only the definitions of the modules built with it are checked." ]
      []
      [ "Build the imported modules (and the libraries they come from) with `--check-universes` too, for instance by adding it to the `opts` of their packages." ]
  ]

||| The entry of a code, if it is one (the letter can be in either case)
export
lookupCode : String -> Maybe ErrorKind
lookupCode c = find (\ k => k.code == toUpper (trim c)) registry

||| The explanation of a code, as plain text
export
explainText : ErrorKind -> String
explainText k
    = unlines $ (k.code ++ ": " ++ k.title) ::
        case k.explanation of
          Nothing => ["", "There is no longer explanation of this error yet."]
          Just ex =>
            [""] ++ intersperse "" ex.summary
            ++ (if null ex.example then []
                   else ["", "Example:", ""] ++ map (\ l => if l == "" then "" else "    " ++ l) ex.example)
            ++ (if null ex.fixes then []
                   else ["", "Usual fixes:", ""] ++ map ("  - " ++) ex.fixes)

||| The reference page of the error codes, in reStructuredText
export
codesRST : String
codesRST
    = unlines $
        [ ".. _sect-error-codes:"
        , ""
        , "***********"
        , "Error codes"
        , "***********"
        , ""
        , ".. This page is printed by `idris2i-1 --list-error-codes` from the registry in"
        , "   src/Idris/ErrorCode.idr; edit that and print it again, as the test"
        , "   idris2i-1/error/errorcodes001 compares the two."
        , ""
        , "Each kind of error and warning has a code, printed in brackets at the end"
        , "of the first line of its message (unless ``--no-error-codes`` is given), and"
        , "as the ``code`` field of JSON diagnostics (``--error-format json``). Errors"
        , "have codes ``E`` followed by four digits, warnings ``W`` and four digits;"
        , "the first two digits are the area. ``idris2i-1 --explain E0101`` (or"
        , "``:explain E0101`` at the REPL) prints the explanation of a code."
        , ""
        , "Codes are never renumbered and never given to another kind of error. A"
        , "kind that is no longer reported keeps its code, and a new kind takes the"
        , "next free code of its area."
        , ""
        , "Summary"
        , "======="
        , ""
        , ".. list-table::"
        , "   :header-rows: 1"
        , ""
        , "   * - Code"
        , "     - Meaning"
        ]
        ++ concatMap (\ k => ["   * - " ++ k.code, "     - " ++ k.title]) registry
        ++ ["", "Explanations", "============", ""]
        ++ concatMap entry (filter (isJust . explanation) registry)
  where
    entry : ErrorKind -> List String
    entry k
        = let heading = k.code ++ ": " ++ k.title in
              [heading, replicate (length heading) '-', ""] ++
              case k.explanation of
                Nothing => []
                Just ex =>
                  intersperse "" ex.summary
                  ++ (if null ex.example then []
                         else ["", ".. code-block:: idris", ""]
                              ++ map (\ l => if l == "" then "" else "    " ++ l) ex.example)
                  ++ (if null ex.fixes then []
                         else ["", "Usual fixes:", ""] ++ map ("* " ++) ex.fixes)
                  ++ [""]
