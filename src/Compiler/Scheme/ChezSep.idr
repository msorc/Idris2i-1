module Compiler.Scheme.ChezSep

import Compiler.Common
import Compiler.CompileExpr
import Compiler.Generated
import Compiler.Scheme.Common
import Compiler.Scheme.Chez
import Compiler.Separate

import Core.Hash
import Core.Directory
import Libraries.Data.String.Builder
import Libraries.Utils.Path

import Data.List1
import Data.String

import Idris.Syntax

import System
import System.Directory
import System.Info

import Libraries.Data.Version
import Libraries.Utils.String

%default covering

schHeader : List String -> List String -> Builder
schHeader libs compilationUnits = fromString """
  (import (chezscheme) (support)
      \{ unwords ["(" ++ cu ++ ")" | cu <- compilationUnits] })
  (case (machine-type)
    [(i3le ti3le a6le ta6le tarm64le) (load-shared-object "libc.so.6")]
    [(i3osx ti3osx a6osx ta6osx tarm64osx tppc32osx tppc64osx) (load-shared-object "libc.dylib")]
    [(i3nt ti3nt a6nt ta6nt) (load-shared-object "msvcrt.dll")]
    [else (load-shared-object "libc.so")]
  \{ unlines ["  (load-shared-object \"" ++ escapeStringChez lib ++ "\")" | lib <- libs] })

  """

schFooter : Builder
schFooter = """

  (collect-request-handler (lambda () (collect (collect-maximum-generation)) (blodwen-run-finalisers)))
  (collect-rendezvous)
  """

startChez : String -> String -> String -> String
startChez chez appDirSh targetSh = Chez.startChezPreamble ++ """
  export LD_LIBRARY_PATH="$DIR/\{ appDirSh }:$LD_LIBRARY_PATH"
  export DYLD_LIBRARY_PATH="$DIR/\{ appDirSh }:$DYLD_LIBRARY_PATH"

  "\{ chez }" -q \
    --libdirs "$DIR/\{ appDirSh }" \
    --program "$DIR/\{ targetSh }" \
    "$@"
  """

startChezCmd : String -> String -> String -> String
startChezCmd chez appDirSh targetSh = """
  @echo off

  rem \{ generatedString "ChezSep" }

  set APPDIR=%~dp0
  set PATH=%APPDIR%\{ appDirSh };%PATH%

  "\{ chez }" -q \
    --libdirs "%APPDIR%\{ appDirSh }" \
    --program "%APPDIR%\{ targetSh }" \
    %*
  """

startChezWinSh : String -> String -> String -> String
startChezWinSh chez appDirSh targetSh = """
  #!/bin/sh
  # \{ generatedString "ChezSep" }

  set -e # exit on any error

  DIR=$(dirname "$(readlink -f -- "$0" || cygpath -a -- "$0")")
  PATH="$DIR/\{ appDirSh }:$PATH"

  "\{ chez }" -q \
    --libdirs "$DIR/\{ appDirSh }" \
    --program "$DIR/\{ targetSh }" \
    "$@"
  """

||| Run Chez on a script that compiles Scheme files, then remove the script.
||| (The script is a file, not a pipe into Chez, so that the arguments are not
||| quoted twice, and an error of Chez stops it and is reported.)
runChezCompile : (chez : String) -> (libDir : String) -> (what : String) ->
                 (script : Builder) -> Core ()
runChezCompile chez libDir what script = do
  let scriptFile = libDir </> "compile-" ++ what ++ ".script"
  Right () <- coreLift $ writeFile scriptFile (build script)
     | Left err => throw (FileErr scriptFile err)
  status <- coreLift $ system [chez, "-q", "--libdirs", libDir, "--script", scriptFile]
  ignore $ coreLift $ removeFile scriptFile
  unless (status == 0) $
    throw (InternalError "Chez exited with return code \{show status} when compiling \{what}")

||| Compile the `compile` (`compile-library` or `compile-program`) of each file,
||| and delete the SS file, to prevent it from interfering with the SO file.
||| We keep the .hash files, though, so we still keep track of what to rebuild.
compileChezFiles : (compile : String) -> (chez : String) -> (libDir : String) ->
                   (what : String) -> (ssFiles : List String) -> Core ()
compileChezFiles compile chez libDir what ssFiles =
  runChezCompile chez libDir what $ concat $
    [ "(parameterize ([optimize-level 3] [compile-file-message #f])\n"
    ] ++
    [ "  (" ++ fromString compile ++ " " ++ chezString ssFile ++ ")\n"
      ++ "  (delete-file " ++ chezString ssFile ++ ")\n"
    | ssFile <- ssFiles
    ] ++ [")\n"]

-- TODO: parallelise this
compileChezLibraries : (chez : String) -> (libDir : String) -> (ssFiles : List String) -> Core ()
compileChezLibraries chez libDir ssFiles =
  compileChezFiles "compile-library" chez libDir "libraries" ssFiles

compileChezLibrary : (chez : String) -> (libDir : String) -> (ssFile : String) -> Core ()
compileChezLibrary chez libDir ssFile =
  compileChezFiles "compile-library" chez libDir "support" [ssFile]

compileChezProgram : (chez : String) -> (libDir : String) -> (ssFile : String) -> Core ()
compileChezProgram chez libDir ssFile =
  compileChezFiles "compile-program" chez libDir "program" [ssFile]

chezNS : Namespace -> String
chezNS ns = case showNSWithSep "-" ns of
  "" => "unqualified"
  nss => nss

-- arbitrarily name the compilation unit
-- after the alphabetically first namespace contained within
chezLibraryName : CompilationUnit def -> String
chezLibraryName cu = chezNS (foldl1 min cu.namespaces)

touch : String -> Core ()
touch s = coreLift_ $ system ["touch", s]

||| Is the code of this name (the .hash file kept by the last successful build) different
||| from the hash, or is its compiled file missing?
outdatedFile : (appdir : String) -> (name : String) -> (hash : String) -> Core Bool
outdatedFile appdir name hash =
  coreLift (readFile (appdir </> name <.> "hash")) >>= \case
    Left err => pure True
    Right fileHash =>
      if fileHash /= hash
         then pure True
         else not <$> coreLift (exists (appdir </> name <.> "so"))

record ChezLib where
  constructor MkChezLib
  name : String
  hash : String      -- of the code and the imports, kept after compiling
  isOutdated : Bool  -- needs recompiling

||| Keep the hashes of the code that Chez has compiled
keepHashes : (appdir : String) -> Maybe String -> List ChezLib -> Core ()
keepHashes appdir supportHash libs = do
  case supportHash of
    Just h => Core.writeFile (appdir </> "support.hash") h
    Nothing => pure ()
  for_ libs $ \lib => when lib.isOutdated $
    Core.writeFile (appdir </> lib.name <.> "hash") lib.hash

||| The units that must be recompiled: the changed ones, and the units that
||| import them, directly or not.  (Chez refuses a compiled library that imports
||| another one that was compiled again afterwards: "requires a different
||| compilation instance".)
propagateChanges : List (CompilationUnit def) ->
                   SortedSet CompilationUnitId -> SortedSet CompilationUnitId
propagateChanges cus outdated =
  let outdated' = foldl add outdated cus
  in if length (Prelude.toList outdated') == length (Prelude.toList outdated)
        then outdated
        else propagateChanges cus outdated'
  where
    add : SortedSet CompilationUnitId -> CompilationUnit def -> SortedSet CompilationUnitId
    add acc cu =
      if any (\d => contains d acc) (Prelude.toList cu.dependencies)
         then insert cu.id acc
         else acc

||| Compile a TT expression to a bunch of Chez Scheme files
||| Returns the hash of the support library, if it must be compiled again, and
||| the units.  The hashes are kept (`keepHashes`) once Chez has compiled the
||| code, so that a failure does not make the next build believe that the units
||| are up to date.
compileToSS : Ref Ctxt Defs -> String -> String -> ClosedTerm -> Core (Maybe String, List ChezLib)
compileToSS c chez appdir tm = do
  -- process native libraries
  ds <- getDirectives Chez
  libs <- findLibs ds
  traverse_ copyLib libs
  version <- coreLift $ chezVersion chez

  -- get the material for compilation
  cdata <- getCompileData False Cases tm
  let ctm = forget (mainExpr cdata)
  let ndefs = namedDefs cdata
  let cui = getCompilationUnits ndefs
  let bt = chezBacktrace ds

  -- copy the support library
  support <- readDataFile "chez/support-sep.ss"
  let supportHash = show $ hash support
  supportChanged <- outdatedFile appdir "support" supportHash
  when supportChanged $
    Core.writeFile (appdir </> "support.ss") support

  -- TODO: add extraRuntime
  -- the problem with this is that it's unclear what to put in the (export) clause of the library
  -- extraRuntime <- getExtraRuntime ds

  -- the names of the imports of the units (and of the units)
  let imports : CompilationUnit (FC, NamedDef) -> List String
      imports cu =
        [ maybe "unqualified" chezLibraryName (SortedMap.lookup cuid cui.byId)
        | cuid <- Prelude.toList cu.dependencies
        ]
  -- (the code of a unit is not the same with `--directive chez-backtrace`)
  let unitHash : CompilationUnit (FC, NamedDef) -> String
      unitHash cu = show (hash cu) ++ "-" ++ show (hash (unwords (imports cu)))
                    ++ (if bt then "-backtrace" else "")

  -- find the units to compile: those that changed (their hash or their SO file),
  -- all of them when the support library changed, and those that import them
  changed <- for cui.compilationUnits $ \cu =>
    if supportChanged then pure True
       else outdatedFile appdir (chezLibraryName cu) (unitHash cu)
  let outdated = propagateChanges cui.compilationUnits $ SortedSet.fromList
        [cu.id | (cu, ch) <- zip cui.compilationUnits changed, ch]

  -- for each compilation unit, generate code
  chezLibs <- for cui.compilationUnits $ \cu => do
    let chezLib = chezLibraryName cu
    let cuHash = unitHash cu
    let isOutdated = contains cu.id outdated

    -- generate code only when necessary
    when isOutdated $ do
      defs <- get Ctxt
      l <- newRef {t = List String} Loaded ["libc", "libc 6"]
      s <- newRef {t = List String} Structs []

      -- create imports + exports + header + footer
      let imports = unwords ["(" ++ i ++ ")" | i <- imports cu]
      let exports = sepBy " " $ catMaybes
            -- constructors don't generate Scheme definitions
            [ case d of
                MkNmCon {} => Nothing
                _ => Just $ schName dn
            | (dn, fc, d) <- cu.definitions
            ]
      let header =
            "(library (" ++ fromString chezLib ++ ")\n"
            ++ "  (export " ++ exports ++ ")\n"
            ++ "  (import (chezscheme) (support) " ++ fromString imports ++ ")\n\n"
      let footer = ")"

      fgndefs <- traverse (Chez.getFgnCall version) cu.definitions
      let ext = Chez.chezExtPrim empty defaultLaziness
      compdefs <- traverse (if bt then getSchemeBacktrace empty ext defaultLaziness
                                  else getScheme empty ext Chez.chezString defaultLaziness) cu.definitions
      loadlibs <- traverse (map fromString . loadLib appdir) (mapMaybe fst fgndefs)

      -- write the files
      log "compiler.scheme.chez" 3 $ "Generating code for " ++ chezLib
      Core.writeFile (appdir </> chezLib <.> "ss") $ build $ concat $
        [header]
        ++ map snd fgndefs  -- definitions using foreign libs
        ++ compdefs
        ++ loadlibs  -- foreign library load statements
        ++ [footer]

    pure (MkChezLib chezLib cuHash isOutdated)

  -- main module
  main <- schExp empty (Chez.chezExtPrim empty defaultLaziness) Chez.chezString defaultLaziness 0 ctm
  btTable <- if bt then backtraceTable ndefs else pure ""
  Core.writeFile (appdir </> "mainprog.ss") $ build $ sepBy "\n"
    [ schHeader (map snd libs) [lib.name | lib <- chezLibs]
    , btTable
    , collectRequestHandler
    , main
    , schFooter
    ]

  pure (toMaybe supportChanged supportHash, chezLibs)

makeSh : String -> String -> String -> String -> Core ()
makeSh chez outShRel appDirSh targetSh =
  Core.writeFile outShRel (startChez chez appDirSh targetSh)

||| Make Windows start scripts, one for bash environments and one batch file
makeShWindows : String -> String -> String -> String -> Core ()
makeShWindows chez outShRel appDirSh targetSh = do
  let cmdFile = outShRel ++ ".cmd"
  Core.writeFile cmdFile (startChezCmd chez appDirSh targetSh)
  Core.writeFile outShRel (startChezWinSh chez appDirSh targetSh)

||| Chez Scheme implementation of the `compileExpr` interface.
compileExpr :
  Bool ->
  Ref Ctxt Defs ->
  Ref Syn SyntaxInfo ->
  (tmpDir : String) -> (outputDir : String) ->
  ClosedTerm -> (outfile : String) -> Core (Maybe String)
compileExpr makeitso c s tmpDir outputDir tm outfile = do
  -- set up paths
  Just cwd <- coreLift currentDir
       | Nothing => throw (InternalError "Can't get current directory")
  let appDirSh  = outfile ++ "_app"  -- relative to the launcher shell script
  let appDirRel = outputDir </> appDirSh  -- relative to CWD
  let appDirAbs = cwd </> appDirRel
  coreLift_ $ mkdirAll appDirRel

  -- generate the code
  chez <- coreLift $ findChez
  (supportHash, chezLibs) <- compileToSS c chez appDirRel tm

  -- compile the code
  logTime 2 "Make SO" $ when makeitso $ do
    -- compile the support code
    when (isJust supportHash) $ do
      log "compiler.scheme.chez" 3 $ "Compiling support"
      compileChezLibrary chez appDirRel (appDirRel </> "support.ss")

    -- compile every compilation unit that changed
    let outdated = [appDirRel </> lib.name <.> "ss" | lib <- chezLibs, lib.isOutdated]
    unless (null outdated) $
      compileChezLibraries chez appDirRel outdated

    -- touch them in the right order to make the timestamps right
    -- even for the libraries that were not recompiled
    for_ chezLibs $ \lib => do
      log "compiler.scheme.chez" 3 $ "Touching " ++ lib.name
      touch (appDirRel </> lib.name <.> "so")

    -- the units are compiled: keep their hashes
    keepHashes appDirRel supportHash chezLibs

    -- compile the main program
    compileChezProgram chez appDirRel (appDirRel </> "mainprog.ss")

  -- generate the launch script
  let outShRel = outputDir </> outfile
  let launchTargetSh = appDirSh </> "mainprog" <.> (if makeitso then "so" else "ss")
  if isWindows
     then makeShWindows chez outShRel appDirSh launchTargetSh
     else makeSh        chez outShRel appDirSh launchTargetSh
  coreLift_ $ chmodRaw outShRel 0o755
  pure (Just outShRel)

||| Chez Scheme implementation of the `executeExpr` interface.
||| This implementation simply runs the usual compiler, saving it to a temp file, then interpreting it.
executeExpr :
  Ref Ctxt Defs ->
  Ref Syn SyntaxInfo ->
  (tmpDir : String) -> ClosedTerm -> Core Int
executeExpr c s tmpDir tm
    = do Just sh <- compileExpr False c s tmpDir tmpDir tm "_tmpchez"
            | Nothing => throw (InternalError "compileExpr returned Nothing")
         runProgram [sh]

||| Codegen wrapper for Chez scheme implementation.
export
codegenChezSep : Codegen
codegenChezSep = MkCG (compileExpr True) executeExpr Nothing Nothing
