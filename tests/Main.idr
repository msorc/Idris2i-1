module Main

import System
import System.Directory
import System.Escape
import System.File

import Data.List
import Data.Maybe
import Data.String

import Test.Golden

%default covering

------------------------------------------------------------------------
-- Test cases

ttimpTests : IO TestPool
ttimpTests = testsInDir "ttimp" "TTImp"

idrisTestsBasic : IO TestPool
idrisTestsBasic = testsInDir "idris2i-1/basic" "Fundamental language features"

idrisTestsDebug : IO TestPool
idrisTestsDebug = testsInDir "idris2i-1/debug" "Debug features"

idrisTestsCoverage : IO TestPool
idrisTestsCoverage = testsInDir "idris2i-1/coverage" "Coverage checking"

idrisTestsTermination : IO TestPool
idrisTestsTermination = testsInDir "idris2i-1/termination" "Termination checking"

idrisTestsCasetree : IO TestPool
idrisTestsCasetree = testsInDir "idris2i-1/casetree" "Case tree building"

idrisTestsWarning : IO TestPool
idrisTestsWarning = testsInDir "idris2i-1/warning" "Warnings"

idrisTestsFailing : IO TestPool
idrisTestsFailing = testsInDir "idris2i-1/failing" "Failing blocks"

||| Error messages, including parse errors ("perror")
idrisTestsError : IO TestPool
idrisTestsError = testsInDir "idris2i-1/error" "Error messages"

idrisTestsInteractive : IO TestPool
idrisTestsInteractive = testsInDir "idris2i-1/interactive" "Interactive editing"

idrisTestsInterface : IO TestPool
idrisTestsInterface = testsInDir "idris2i-1/interface" "Interface"

||| QTT and linearity related
idrisTestsLinear : IO TestPool
idrisTestsLinear = testsInDir "idris2i-1/linear" "Quantities"

idrisTestsLiterate : IO TestPool
idrisTestsLiterate = testsInDir "idris2i-1/literate" "Literate programming"

||| Performance: things which have been slow in the past, or which
||| pose interesting challenges for the elaborator
idrisTestsPerformance : IO TestPool
idrisTestsPerformance = testsInDir "idris2i-1/perf" "Performance"

idrisTestsRegression : IO TestPool
idrisTestsRegression = testsInDir "idris2i-1/reg" "Various regressions"

||| Data types, including records
idrisTestsData : IO TestPool
idrisTestsData = testsInDir "idris2i-1/data" "Data and record types"

||| %builtin related tests for the frontend (type-checking)
idrisTestsBuiltin : IO TestPool
idrisTestsBuiltin = testsInDir "idris2i-1/builtin" "Builtin types and functions"

||| Evaluator, REPL, specialisation
idrisTestsEvaluator : IO TestPool
idrisTestsEvaluator = testsInDir "idris2i-1/evaluator" "Evaluation"

idrisTestsREPL : IO TestPool
idrisTestsREPL = testsInDir "idris2i-1/repl" "REPL commands and help"

||| Regressions for proofs of false
idrisTestsFalse : IO TestPool
idrisTestsFalse = testsInDir "idris2i-1/false" "Proof of false regressions"

idrisTestsAllSchemes : Requirement -> IO TestPool
idrisTestsAllSchemes cg = testsInDir "allschemes"
      ("Test across all scheme backends: " ++ show cg ++ " instance")
      {codegen = Just cg}

idrisTestsAllBackends : Requirement -> IO TestPool
idrisTestsAllBackends cg = testsInDir "allbackends"
      ("Test across all backends: " ++ show cg ++ " instance")
      {codegen = Just cg}
      {pred = not . (`elem` exclude)}
  where
    -- Some tests are known to fail on some backends
    exclude : List String
    exclude = catMaybes
      [ -- RefC implements IEEE standard and distinguishes between 0.0 and -0.0
        -- unlike other backends. So turn this test for now.
        toMaybe (cg == C) "issue2362"
        -- Unfortunately the behaviour of Double is platform dependent so the
        -- following test is turned off.
      , Just "evaluator005"
      ]

||| Totality checking, including positivity
idrisTestsTotality : IO TestPool
idrisTestsTotality = testsInDir "idris2i-1/total" "Totality checking"

||| The Scheme evaluator (`:set eval scheme`) runs the code in the Scheme
||| system that the compiler runs on, so it only works with a compiler
||| compiled with Chez.  Ask the compiler under test whether it
||| evaluates with Scheme: a compiler compiled with another backend (RefC, the
||| default) says that the Scheme evaluator is not available, and the tests
||| are skipped.  Whatever else happens (the evaluator gives a wrong result, or
||| cannot load its support code, or the compiler fails) is a fault of the
||| evaluator, which the tests must show: they run then.
schemeHosted : (idris2i_1 : String) -> Requirement
schemeHosted idris2i_1 = MkReq "Scheme evaluator" $ do
    (out, _) <- run $ "printf ':set eval scheme\\nthe Integer (6 * 7)\\n:q\\n' | "
                        ++ escapeArg idris2i_1 ++ " --no-banner --no-color --console-width 0 2>&1"
    pure $ toMaybe (not ("Scheme evaluator not available" `isInfixOf` out)) idris2i_1

idrisTestsSchemeEval : (idris2i_1 : String) -> IO TestPool
idrisTestsSchemeEval idris2i_1 = testsInDir "idris2i-1/schemeeval" "Scheme Evaluator"
  {requirements = [schemeHosted idris2i_1]}

idrisTestsReflection : IO TestPool
idrisTestsReflection = testsInDir "idris2i-1/reflection" "Quotation and Reflection"

idrisTestsWith : IO TestPool
idrisTestsWith = testsInDir "idris2i-1/with" "With abstraction"

idrisTestsOperators : IO TestPool
idrisTestsOperators = testsInDir "idris2i-1/operators" "Operator and fixities"

idrisTestsIPKG : IO TestPool
idrisTestsIPKG = testsInDir "idris2i-1/pkg" "Package and .ipkg files"

idrisTestsMkdoc : IO TestPool
idrisTestsMkdoc = testsInDir "idris2i-1/mkdoc" "HTML documentation generator"

idrisTestsMisc : IO TestPool
idrisTestsMisc = testsInDir "idris2i-1/misc" "Misc"

typeddTests : IO TestPool
typeddTests = testsInDir "typedd-book" "Type Driven Development"

chezTests : IO TestPool
chezTests = testsInDir "chez" "Chez backend"
  {codegen = Just Chez}
  {pred = not . ("channels009" ==)}

||| `--cg chez-sep`: every module is a Chez library of its own.  The tests ask
||| for this back end themselves, so the pool needs Chez but no code generator.
chezSepTests : IO TestPool
chezSepTests = testsInDir "chezsep" "Chez backend with separate compilation"
  {requirements = [Chez]}

refcTests : IO TestPool
refcTests = testsInDir "refc" "Reference counting C backend" {codegen = Just C}

nodeTests : IO TestPool
nodeTests = testsInDir "node" "Node backend" {codegen = Just Node}

vmcodeInterpTests : IO TestPool
vmcodeInterpTests = testsInDir "vmcode" "VMCode interpreter"

ideModeTests : IO TestPool
ideModeTests = testsInDir "ideMode" "IDE mode"

preludeTests : IO TestPool
preludeTests = testsInDir "prelude" "Prelude library"

templateTests : IO TestPool
templateTests = testsInDir "templates" "Test templates"

-- base library tests are run against
-- each codegen supported and to keep
-- things simple it's all one test group
-- that only runs if all backends are
-- available.
baseLibraryTests : IO TestPool
baseLibraryTests = testsInDir "base" "Base library" {requirements = [Chez, Node]}

-- same behavior as `baseLibraryTests`
contribLibraryTests : IO TestPool
contribLibraryTests = testsInDir "contrib" "Contrib library" {requirements = [Chez, Node]}

-- same behavior as `baseLibraryTests`
linearLibraryTests : IO TestPool
linearLibraryTests = testsInDir "linear" "Linear library" {requirements = [Chez, Node]}

-- The http library (libs/http), with the default code generator.
httpLibraryTests : IO TestPool
httpLibraryTests = testsInDir "http" "HTTP library"

-- The tls library (libs/tls) is optional: it is in the test environment
-- (IDRIS2I_1_PREFIX) only when it was built, with OpenSSL 3, and so is the
-- http-tls library, which needs it.  Their tests make their certificates
-- with the openssl command-line tool.
optionalLibrary : (name : String) -> Requirement
optionalLibrary name = MkReq "\{name} library" $ do
    Just tool <- pathLookup ["openssl"]
      | Nothing => pure Nothing
    Just dir <- getEnv "IDRIS2I_1_PREFIX"
      | Nothing => pure Nothing
    Right ds <- listDir dir
      | Left _ => pure Nothing
    found <- for (filter (isPrefixOf "idris2i-1-") ds) $ \d => do
               Right ps <- listDir (dir ++ "/" ++ d)
                 | Left _ => pure False
               pure (any (isPrefixOf (name ++ "-")) ps)
    pure $ toMaybe (or (map delay found)) tool

tlsLibraryTests : IO TestPool
tlsLibraryTests = testsInDir "tls" "TLS library" {requirements = [optionalLibrary "tls"]}

httpTLSLibraryTests : IO TestPool
httpTLSLibraryTests = testsInDir "http-tls" "HTTPS (http-tls library)" {requirements = [optionalLibrary "http-tls"]}

codegenTests : IO TestPool
codegenTests = testsInDir "codegen" "Code generation"

commandLineTests : IO TestPool
commandLineTests = testsInDir "cli" "Command-line interface"

main : IO ()
main = do
  args <- getArgs
  Just opts <- options args
    | _ => do printLn args
              putStrLn usage
  runnerWith opts =<< sequence (pools opts.exeUnderTest)
  where
    pools : String -> List (IO TestPool)
    pools idris2i_1 =
      [ ttimpTests
      , idrisTestsBasic
      , idrisTestsCoverage
      , idrisTestsTermination
      , idrisTestsCasetree
      , idrisTestsError
      , idrisTestsFailing
      , idrisTestsWarning
      , idrisTestsInteractive
      , idrisTestsInterface
      , idrisTestsLiterate
      , idrisTestsLinear
      , idrisTestsPerformance
      , idrisTestsRegression
      , idrisTestsData
      , idrisTestsBuiltin
      , idrisTestsEvaluator
      , idrisTestsREPL
      , idrisTestsFalse
      , idrisTestsTotality
      , idrisTestsSchemeEval idris2i_1
      , idrisTestsReflection
      , idrisTestsWith
      , idrisTestsOperators
      , idrisTestsDebug
      , idrisTestsIPKG
      , idrisTestsMkdoc
      , idrisTestsMisc
      , typeddTests
      , ideModeTests
      , preludeTests
      , baseLibraryTests
      , linearLibraryTests
      , contribLibraryTests
      , httpLibraryTests
      , tlsLibraryTests
      , httpTLSLibraryTests
      , chezTests
      , chezSepTests
      , refcTests
      , nodeTests
      , vmcodeInterpTests
      , templateTests
      , codegenTests
      , commandLineTests
      ]
      ++ map idrisTestsAllSchemes [Chez]
      ++ map idrisTestsAllBackends [Chez, Node, C]
