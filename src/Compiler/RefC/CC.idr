module Compiler.RefC.CC

import Core.Context.Log
import Core.Options
import Core.Directory

import System
import System.Directory
import System.File
import System.Info
import Idris.Env

import Data.List
import Data.String

import Libraries.Utils.Path

%default total

||| The C compiler: `IDRIS2I_1_CC`, `CC` or `cc`.  It is a single program (a
||| name looked for in the `PATH`, or a path, which may contain spaces), not a
||| command line: `ccache gcc` is not a C compiler.
export
findCC : IO String
findCC
    = do Nothing <- idrisGetEnv "IDRIS2I_1_CC"
           | Just cc => pure cc
         Nothing <- idrisGetEnv "CC"
           | Just cc => pure cc
         pure "cc"

-- Without optimisation, the inline functions of the runtime (reference
-- counting, allocation) are not inlined, which makes the code several times
-- slower: -O2 comes first, so that the flags of the user (`-g`, `-Wall`) keep
-- it, and a later `-O` of theirs wins.
findCFLAGS : IO String
findCFLAGS
  = do Nothing <- idrisGetEnv "IDRIS2I_1_CFLAGS"
         | Just cflags => pure ("-O2 " ++ cflags)
       Nothing <- idrisGetEnv "CFLAGS"
         | Just cflags => pure ("-O2 " ++ cflags)
       pure "-O2"

findCPPFLAGS : IO String
findCPPFLAGS
  = do Nothing <- idrisGetEnv "IDRIS2I_1_CPPFLAGS"
         | Just cppflags => pure cppflags
       Nothing <- idrisGetEnv "CPPFLAGS"
         | Just cppflags => pure cppflags
       pure ""

export
findLDFLAGS : IO String
findLDFLAGS
  = do Nothing <- idrisGetEnv "IDRIS2I_1_LDFLAGS"
         | Just ldflags => pure ldflags
       Nothing <- idrisGetEnv "LDFLAGS"
         | Just ldflags => pure ldflags
       pure ""

findLDLIBS : IO String
findLDLIBS
  = do Nothing <- idrisGetEnv "IDRIS2I_1_LDLIBS"
         | Just ldlibs => pure ldlibs
       Nothing <- idrisGetEnv "LDLIBS"
         | Just ldlibs => pure ldlibs
       pure ""

clibdirs : List String -> List String
clibdirs ds = map (\d => "-L" ++ d) ds

------------------------------------------------------------------------
-- What the directives of a program add to the C compiler and the linker

%default covering
--
-- A library that wraps a C library tells what to link with directives,
-- which `%cg refc <directive>` in a module stores in its TTC file, so that
-- every program that imports the module gets them (`--directive` gives them
-- on the command line, or in the `opts` of a package):
--
--   refc-lib=<names>        `-l<name>` for each name
--   refc-archive=<files>    a static archive (or an object file) of the
--                           package, found in the `lib` directories (see
--                           `findLibraryFile`), passed by its path
--   refc-pkg-config=<names> the output of `pkg-config --cflags` on the C
--                           compiler's command line, and of `--libs` on the
--                           linker's
--
-- A directive may give several names, separated by spaces, which keep their
-- order.  The archives come first, then the libraries, then the flags of
-- pkg-config, all after the object files of the program and before the
-- support libraries of the runtime (an archive may call the runtime).  The
-- directives of the command line come first, in their order, then those of
-- the modules, sorted by their text (they are a set); a name that comes more
-- than once is kept at its last place, so that a library stays after those
-- that need it.

||| The RefC directives without a value.
refcFlagDirectives : List String
refcFlagDirectives
    = [ "refc-backtrace", "refc-check-layout", "refc-flat-arrays"
      , "refc-no-borrow", "refc-no-cold-constants", "refc-no-cycle-safepoints"
      , "refc-no-direct-results"
      , "refc-no-exact-rebuild"
      , "refc-no-flat-arrays", "refc-no-gc-sections"
      , "refc-no-lazy-constants", "refc-no-local-closures"
      , "refc-no-merge-closures", "refc-no-merge-rounds"
      , "refc-no-multi-reuse", "refc-no-raw-fields", "refc-no-reuse-copy"
      , "refc-no-static", "refc-no-trmc", "refc-no-unbox-double"
      , "refc-no-workers", "refc-size-reuse" ]

||| The RefC directives with a value, `name=value`.
refcValueDirectives : List String
refcValueDirectives
    = [ "refc-archive", "refc-lib", "refc-pkg-config", "refc-split-size" ]

-- A directive split at its first `=`: the value is Nothing without one.
splitDirective : String -> (String, Maybe String)
splitDirective d
    = case break (== '=') (unpack (trim d)) of
           (key, []) => (pack key, Nothing)
           (key, _ :: value) => (pack key, Just (pack value))

-- Names of libraries and pkg-config modules: no options, no shell syntax.
nameChar : Char -> Bool
nameChar ch = isAlphaNum ch || elem ch (unpack "_.+-:")

directiveError : String -> String -> Core a
directiveError d why
    = throw (GenericMsg emptyFC "The RefC directive \{show (trim d)} \{why}")

-- The names of the value of a directive.
directiveNames : (d : String) -> (key : String) -> (value : String) ->
                 Core (List String)
directiveNames d key value
    = do let ns = words value
         when (null ns) $ directiveError d "gives no name"
         for_ ns $ \n =>
           do when (isPrefixOf "-" n) $
                directiveError d $ case key of
                  "refc-lib" => "gives \{show n}: the names of the libraries come without -l (refc-lib=ssl for -lssl)"
                  _ => "gives \{show n}, which is an option and not a name"
              when (key /= "refc-archive" && not (all nameChar (unpack n))) $
                directiveError d "gives \{show n}, which is not the name of a library"
         pure ns

-- Keep the last place of every element.
nubLast : Eq a => List a -> List a
nubLast = reverse . nub . reverse

-- The names that the directives `key=...` give, in order (see above).
directiveValues : {auto c : Ref Ctxt Defs} -> (key : String) -> Core (List String)
directiveValues key
    = do -- (`getDirectives` gives those of the command line last first)
         defs <- get Ctxt
         let n = length defs.options.session.directives
         ds <- map (\ds => reverse (take n ds) ++ drop n ds) (getDirectives RefC)
         names <- traverse (\d => case splitDirective d of
                                       (k, Just v) => if k == key
                                                         then directiveNames d key v
                                                         else pure []
                                       _ => pure []) ds
         pure (nubLast (concat names))

||| The archives of `refc-archive` directives, as they are found in the
||| library directories (see `findLibraryFile`), in the order of the link.
export
refcArchives : {auto c : Ref Ctxt Defs} -> Core (List String)
refcArchives
    = do names <- directiveValues "refc-archive"
         paths <- traverse find names
         pure (nubLast paths)
  where
    find : String -> Core String
    find n = catch (findLibraryFile n)
                   (\_ => do d <- getDirs
                             let dirs = lib_dirs d ++ map (</> "lib") (package_dirs d ++ extra_dirs d)
                             directiveError ("refc-archive=" ++ n) $
                               "names a file that is not in any of the library directories: "
                                 ++ joinBy ", " dirs)

||| The libraries of `refc-lib` directives, in the order of the link.
export
refcLibs : {auto c : Ref Ctxt Defs} -> Core (List String)
refcLibs = directiveValues "refc-lib"

||| The modules of `refc-pkg-config` directives.
export
refcPkgConfigs : {auto c : Ref Ctxt Defs} -> Core (List String)
refcPkgConfigs = directiveValues "refc-pkg-config"

-- The output of a command, when it succeeds.
commandOutput : String -> IO (Maybe String)
commandOutput cmd
    = do Right f <- popen cmd Read
           | Left _ => pure Nothing
         Right out <- fRead f
           | Left _ => do _ <- pclose f
                          pure Nothing
         status <- pclose f
         pure (if status == 0 then Just out else Nothing)

||| The pkg-config program: `PKG_CONFIG`, or `pkg-config`.
findPkgConfig : IO String
findPkgConfig = map (fromMaybe "pkg-config") (getEnv "PKG_CONFIG")

||| What `pkg-config <what> <module>` prints (on one line), or Nothing when it
||| fails (it is not installed, or does not know the module).
export
pkgConfigOutput : (what : String) -> (module_ : String) -> IO (Maybe String)
pkgConfigOutput what m
    = do pc <- findPkgConfig
         map (map (unwords . words)) $
           commandOutput (escapeCmd [pc, what, m] ++ " 2>/dev/null")

-- The flags that pkg-config gives for the modules of the program.
pkgConfigFlags : {auto c : Ref Ctxt Defs} -> (what : String) -> Core String
pkgConfigFlags what
    = do ms <- refcPkgConfigs
         flags <- traverse one ms
         pure (unwords flags)
  where
    one : String -> Core String
    one m = do Just out <- coreLift $ pkgConfigOutput what m
                 | Nothing => do pc <- coreLift findPkgConfig
                                 directiveError ("refc-pkg-config=" ++ m) $
                                   "cannot be used: `\{pc} \{what} \{m}` fails "
                                     ++ "(is pkg-config installed, and does it know \{show m}? "
                                     ++ "PKG_CONFIG_PATH tells it where to look)"
               pure out

||| Check the RefC directives of a program (those that start with `refc-`):
||| an unknown one, or one with a value that cannot be, is an error, rather
||| than something that is silently ignored or that makes the C compiler
||| fail later.
export
checkRefCDirectives : {auto c : Ref Ctxt Defs} -> Core ()
checkRefCDirectives
    = do traverse_ check !(getDirectives RefC)
         -- (the archives must be there, and pkg-config must know the modules)
         ignore refcArchives
         ignore (pkgConfigFlags "--libs")
  where
    check : String -> Core ()
    check d
        = do let (key, value) = splitDirective d
             when (isPrefixOf "refc-" key) $ case value of
               Nothing =>
                 unless (key `elem` refcFlagDirectives) $
                   directiveError d $
                     if key `elem` refcValueDirectives
                        then "needs a value (\{key}=...)"
                        else "is not known"
               Just v =>
                 if key == "refc-split-size"
                    then when (isNothing (parsePositive {a = Nat} (trim v))) $
                           directiveError d "needs a number"
                    else if key `elem` refcValueDirectives
                       then ignore (directiveNames d key v)
                       else directiveError d $
                              if key `elem` refcFlagDirectives
                                 then "takes no value"
                                 else "is not known"

||| The `lib` directories of the packages (and of the `IDRIS2I_1_PATH`), where
||| the headers that a package ships with its C code are looked for.
packageLibDirs : {auto c : Ref Ctxt Defs} -> Core (List String)
packageLibDirs
    = do d <- getDirs
         pure (map (</> "lib") (package_dirs d ++ extra_dirs d))

||| Is the program linked with garbage collection of sections?  Every
||| function of the generated code and of the runtime is in a section of its
||| own (`-ffunction-sections`; the runtime is also built with
||| `-fdata-sections`), and the linker drops the sections that nothing
||| reaches (`--gc-sections`): a hello world loses about half of its file,
||| the parts of the runtime that it never calls (casts, string and
||| arithmetic primitives, ...), and a big program the out-of-line copies
||| of the functions that the C compiler inlined everywhere.  Only on Unix
||| systems other than macOS, whose linkers (GNU ld, gold, lld, mold) all
||| have `--gc-sections`; `--directive refc-no-gc-sections` turns it off.
gcSections : {auto c : Ref Ctxt Defs} -> Core Bool
gcSections
    = do ds <- getDirectives RefC
         pure (os == "unix" && not ("refc-no-gc-sections" `elem` map trim ds))

-- The flags of the C compiler that do not depend on the file: the include
-- directories of the runtime and of the packages, the flags of
-- `refc-pkg-config` directives and those of the user (last, so that they
-- can undo the others).
ccFlags : {auto c : Ref Ctxt Defs} -> Core String
ccFlags =
  do cFlags <- coreLift findCFLAGS
     cppFlags <- coreLift findCPPFLAGS
     refcDir <- findDataFile "refc"
     cDir <- findDataFile "c"
     pkgDirs <- packageLibDirs
     pkgConfig <- pkgConfigFlags "--cflags"
     sections <- gcSections
     pure $ escapeCmd (["-I" ++ refcDir, "-I" ++ cDir] ++ map ("-I" ++) pkgDirs)
              ++ " " ++ pkgConfig ++ " " ++ cppFlags
              ++ (if sections then " -ffunction-sections " else " ") ++ cFlags

-- The command that runs the C compiler on `sourceFile`, writing `outFile`,
-- with the flags `mode` (what to make) and `flags` (see `ccFlags`).
ccCommandWith : (cc : String)
             -> (flags : String)
             -> (mode : List String)
             -> (asLibrary : Bool)
             -> (sourceFile : String)
             -> (outFile : String)
             -> String
ccCommandWith cc flags mode asLibrary sourceFile outFile =
  let libraryFlag = if asLibrary then ["-fpic"] else [] in
  escapeCmd ([cc] ++ mode ++ libraryFlag ++ [sourceFile, "-o", outFile])
    ++ " " ++ flags

-- The command that runs the C compiler on `sourceFile`, writing `outFile`,
-- with the flags `mode` (what to make), the include directories of the
-- runtime and the flags of the user.
ccCommand : {auto c : Ref Ctxt Defs}
         -> (mode : List String)
         -> (asLibrary : Bool)
         -> (sourceFile : String)
         -> (outFile : String)
         -> Core String
ccCommand mode asLibrary sourceFile outFile =
  do cc <- coreLift findCC
     flags <- ccFlags
     pure (ccCommandWith cc flags mode asLibrary sourceFile outFile)

-- The command that compiles `sourceFile` to `objectFile`.
ccObjectCommand : {auto c : Ref Ctxt Defs}
               -> (asLibrary : Bool)
               -> (sourceFile : String)
               -> (objectFile : String)
               -> Core String
ccObjectCommand = ccCommand ["-Werror", "-c"]

export
compileCObjectFile : {auto c : Ref Ctxt Defs}
                  -> {default False asLibrary : Bool}
                  -> (sourceFile : String)
                  -> (objectFile : String)
                  -> Core (Maybe String)
compileCObjectFile {asLibrary} sourceFile objectFile =
  do runccobj <- ccObjectCommand asLibrary sourceFile objectFile
     log "compiler.refc.cc" 10 runccobj
     0 <- coreLift $ system runccobj
       | _ => pure Nothing

     pure (Just objectFile)

-- How many C compilers to run at once: IDRIS2I_1_CC_JOBS, or the number of
-- processors up to 16 (the limit of the Makefile for IDRIS2I_1_JOBS too): each
-- C compiler of a unit of the compiler itself needs a few hundred MB, and
-- more of them gain little.  An IDRIS2I_1_CC_JOBS that is not a number of at
-- least 1 (0, empty, ...) is as if it was not set: with no C compiler
-- running, nothing would be compiled.
findCCJobs : IO Nat
findCCJobs
  = do Just n <- map (>>= parsePositive {a = Nat}) (idrisGetEnv "IDRIS2I_1_CC_JOBS")
         | Nothing => byDefault
       if n >= 1 then pure n else byDefault
  where
    byDefault : IO Nat
    byDefault = map (max 1 . min 16 . fromMaybe 1) getNProcessors

------------------------------------------------------------------------
-- Compiling a big program in units, and reusing their object files
--
-- generateCSourceFileParts (see Compiler.RefC.RefC) writes a big program as
-- many units, C files of their own with the declarations that each needs,
-- next to the single file that has all of them.  An object file is reused
-- when it was made by the same C compiler with the same flags from a unit
-- with exactly the same text, under the same runtime headers: the text of the
-- unit that was compiled last stays in `<base>.u<k>.c` and is compared with
-- the new one, and everything else that decides the object is in the
-- "environment key" `<base>.ukey` (the compiler, its flags, the runtime
-- headers), which is compared as a whole.  An object file is made under a
-- temporary name and renamed when the C compiler succeeds, and it is removed
-- before its unit is written anew, so that an object file that exists is the
-- result of the unit that is next to it.  Nothing is hashed: the texts are
-- compared, so that a collision cannot give a wrong object file.

%default covering

||| The units of a program being compiled.
export
record Units where
  constructor MkUnits
  baseName : String
  asLib : Bool
  ||| May the object files of an earlier run be reused (see `prepareUnits`)?
  reuseObjs : Bool

-- Remove a file, if it is there.
rm : String -> Core ()
rm f = coreLift_ (removeFile f)

||| The most units that a program has: the files of earlier builds are
||| cleaned up below that number (generateCSourceFileParts makes at most
||| that many).
export
maxUnits : Nat
maxUnits = 256

unitSource : Units -> Nat -> String
unitSource u k = u.baseName ++ ".u" ++ show k ++ ".c"

unitObject : Units -> Nat -> String
unitObject u k = u.baseName ++ ".u" ++ show k ++ ".o"

keyFile : Units -> String
keyFile u = u.baseName ++ ".ukey"

-- The `.h` files below a directory, in a fixed order, with their contents.
-- Nothing when one cannot be read.
headerTexts : String -> IO (Maybe (List String))
headerTexts dir
  = do Right entries <- listDir dir
         | Left _ => pure Nothing
       texts <- traverse one (sort entries)
       pure (map concat (sequence texts))
  where
    one : String -> IO (Maybe (List String))
    one e
      = do let path = dir ++ "/" ++ e
           if ".h" `isSuffixOf` e
              then do Right txt <- readFile path
                        | Left _ => pure Nothing
                      pure (Just ["// " ++ path ++ "\n", txt, "\n"])
              else do Right _ <- listDir path
                        | Left _ => pure (Just []) -- not a header, not a directory
                      headerTexts path

-- What the C compiler is: its version and target.
ccIdentity : String -> IO (Maybe String)
ccIdentity cc
  = do Just v <- run (escapeCmd [cc, "--version"] ++ " 2>&1")
         | Nothing => pure Nothing
       Just m <- run (escapeCmd [cc, "-dumpmachine"] ++ " 2>&1")
         | Nothing => pure Nothing
       pure (Just (v ++ m))
  where
    run : String -> IO (Maybe String)
    run cmd
      = do Right f <- popen cmd Read
             | Left _ => pure Nothing
           Right out <- fRead f
             | Left _ => do _ <- pclose f
                            pure Nothing
           status <- pclose f
           pure (if status == 0 then Just out else Nothing)

||| The variables, other than the flags, that a C compiler reads and that
||| change what it makes of a file.
export
ccEnvVars : List String
ccEnvVars = ["CPATH", "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "SDKROOT",
             "GCC_EXEC_PREFIX", "COMPILER_PATH", "LIBRARY_PATH",
             "SOURCE_DATE_EPOCH", "DEPENDENCIES_OUTPUT", "SUNPRO_DEPENDENCIES"]

-- The files that a rule of `make`, as `cc -M -MT x` writes it, depends on
-- (`x: a b \<newline> c`, with the spaces in names as `\ `, `#` as `\#` and
-- `$` as `$$`).
makeDeps : String -> List String
makeDeps txt = case break (== ':') (unpack txt) of
                    (_, _ :: rest) => tokens [] rest
                    _ => []
  where
    done : List Char -> List String -> List String
    done [] rest = rest
    done acc rest = pack (reverse acc) :: rest

    tokens : List Char -> List Char -> List String
    tokens acc [] = done acc []
    tokens acc ('\\' :: '\n' :: cs) = done acc (tokens [] cs)
    tokens acc ('\\' :: '\r' :: '\n' :: cs) = done acc (tokens [] cs)
    tokens acc ('\\' :: ' ' :: cs) = tokens (' ' :: acc) cs
    tokens acc ('\\' :: '#' :: cs) = tokens ('#' :: acc) cs
    tokens acc ('$' :: '$' :: cs) = tokens ('$' :: acc) cs
    tokens acc (c :: cs) = if isSpace c then done acc (tokens [] cs)
                                        else tokens (c :: acc) cs

||| The files, other than the runtime headers in the support directories, that
||| the C compiler reads when it compiles a program that includes `headers`:
||| the headers that are not in the support directories, and those that they
||| include, as the C compiler finds them (with `-M`), with their texts.
||| `Just []` when all the headers are in the support directories, `Nothing`
||| when the files cannot be found out.  `base` is the name of the program
||| without `.c`, next to which a file is written and removed.
export
extraHeaderFiles : {auto c : Ref Ctxt Defs}
                -> {default False asLibrary : Bool}
                -> (base : String)
                -> (headers : List String)
                -> Core (Maybe (List (String, String)))
extraHeaderFiles {asLibrary} base headers =
  do refcDir <- findDataFile "refc"
     cDir <- findDataFile "c"
     known <- coreLift $ traverse (\h => do a <- exists (refcDir ++ "/" ++ h)
                                            b <- exists (cDir ++ "/" ++ h)
                                            pure (a || b)) headers
     -- (a POSIX shell runs the C compiler)
     if all id known then pure (Just []) else if isWindows then pure Nothing else do
       let src = base ++ ".hdeps.c"
       let out = base ++ ".hdeps.d"
       Right () <- coreLift $ writeFile src $
                     concatMap (\h => "#include <" ++ h ++ ">\n") ("runtime.h" :: headers)
         | Left err => throw $ FileErr src err
       cmd <- ccCommand ["-M", "-MT", "x"] asLibrary src out
       log "compiler.refc.cc" 10 cmd
       status <- coreLift $ system (cmd ++ " 2>/dev/null")
       deps <- coreLift $ readFile out
       rm src
       rm out
       let support : String -> Bool
           support f = isPrefixOf (refcDir ++ "/") f || isPrefixOf (cDir ++ "/") f
       let files = case (status, deps) of
                        (0, Right txt) => Just (filter (\f => f /= src && not (support f))
                                                       (makeDeps txt))
                        _ => Nothing
       texts <- coreLift $ traverse (traverse (\f => map (map (\t => (f, t)) . eitherToMaybe)
                                                         (readFile f))) files
       let result = texts >>= sequence
       when (isNothing result) $
         log "compiler.refc.cc" 2 $
           "Cannot find out which files the C compiler reads for the headers "
             ++ show headers
       pure result
  where
    eitherToMaybe : Either e a -> Maybe a
    eitherToMaybe (Left _) = Nothing
    eitherToMaybe (Right x) = Just x

||| The file where a compilation of `<base>.c` lists the files, other than
||| the runtime, that the headers of the program are made of (see
||| `extraHeaderFiles`), for the stamp of an executable (see Idris.ExecStamp):
||| a first line `headerDepsLine` and one file per line, or a single line
||| `unknown` when the files cannot be found out.  There is no file when the
||| headers are all in the support directories.
export
headerDepsFile : (base : String) -> String
headerDepsFile base = base ++ ".hdeps"

export
headerDepsLine : String
headerDepsLine = "idris2i-1 refc header files 1"

||| Write (or remove) the `headerDepsFile` of a program.
export
writeHeaderDeps : (base : String) -> Maybe (List (String, String)) -> Core ()
writeHeaderDeps base (Just []) = rm (headerDepsFile base)
writeHeaderDeps base files
    = do let file = headerDepsFile base
         let ls = maybe ["unknown"] (\fs => headerDepsLine :: map fst fs) files
         Right () <- coreLift $ writeFile file (unlines ls)
           | Left err => throw $ FileErr file err
         pure ()

||| Get the units of a program ready: find out whether the object files of the
||| last build may be reused, which is when they were made in the same
||| environment (the C compiler and its version, `IDRIS2I_1_CC`, `IDRIS2I_1_CFLAGS`,
||| `IDRIS2I_1_CPPFLAGS`, `-fpic`, the include directories, the contents of the
||| headers of the runtime in the `refc` and `c` support directories, the
||| variables that the compiler reads, and the contents of `extra`, the
||| other headers that the program includes, see `extraHeaderFiles`), and
||| remove them when they were not.  If `extra` is not known, nothing is
||| reused.
export
prepareUnits : {auto c : Ref Ctxt Defs}
            -> {default False asLibrary : Bool}
            -> (base : String)
            -> (extra : Maybe (List (String, String)))
            -> Core Units
prepareUnits {asLibrary} base extra =
  do let units = MkUnits base asLibrary False
     cc <- coreLift findCC
     cmd <- ccObjectCommand asLibrary "UNIT.c" "UNIT.o"
     refcDir <- findDataFile "refc"
     cDir <- findDataFile "c"
     Just idt <- coreLift $ ccIdentity cc
       | Nothing => noReuse units "the C compiler \{show cc} does not tell its version"
     Just hs1 <- coreLift $ headerTexts refcDir
       | Nothing => noReuse units "the headers in \{refcDir} cannot be read"
     Just hs2 <- coreLift $ headerTexts cDir
       | Nothing => noReuse units "the headers in \{cDir} cannot be read"
     Just ex <- pure extra
       | Nothing => noReuse units "the files of the headers of the program are not known"
     envs <- coreLift $ traverse (\v => map (\x => v ++ "=" ++ fromMaybe "" x ++ "\n")
                                            (getEnv v)) ccEnvVars
     let key = unlines ["idris2i-1 refc units 1", cmd, idt, concat envs]
                 ++ concat hs1 ++ concat hs2
                 ++ concatMap (\(f, t) => "// " ++ f ++ "\n" ++ t ++ "\n") ex
     old <- coreLift $ readFile (keyFile units)
     unless (either (const False) (== key) old) $
       do log "compiler.refc.cc" 5 "Not reusing object files: their environment changed"
          removeObjs units
          _ <- coreLift $ writeFile (keyFile units) key
          pure ()
     pure ({ reuseObjs := True } units)
  where
    removeObjs : Units -> Core ()
    removeObjs u = for_ [0 .. minus maxUnits 1] $ \k => rm (unitObject u k)
    noReuse : Units -> String -> Core Units
    noReuse u why
        = do log "compiler.refc.cc" 2 "Not reusing object files: \{why}"
             removeObjs u
             rm (keyFile u)
             pure u

||| Write the unit `k` with the text `text`, unless it is the text that was
||| compiled to the object file that is still there.  Returns whether it must
||| be compiled.
export
updateUnit : {auto c : Ref Ctxt Defs}
          -> Units -> (k : Nat) -> (text : String) -> Core Bool
updateUnit u k text =
  do let src = unitSource u k
     let obj = unitObject u k
     here <- coreLift $ exists obj
     same <- if u.reuseObjs && here
                then do Right old <- coreLift $ readFile src
                          | Left _ => pure False
                        pure (old == text)
                else pure False
     if same
        then pure False
        else do rm obj
                Right () <- coreLift $ writeFile src text
                  | Left err => throw $ FileErr src err
                pure True

||| Compile the units that `updateUnit` says need it (`todo`, with their
||| sizes), the biggest first, with at most IDRIS2I_1_CC_JOBS (the number of
||| processors, up to 16) C compilers running at once.  `present` are the units of the
||| program, whose object files are returned: the files of other units, of
||| earlier builds, are removed.
export
compileUnits : {auto c : Ref Ctxt Defs}
            -> Units
            -> (present : List Nat)
            -> (todo : List (Nat, Nat))
            -> Core (Maybe (List String))
compileUnits u present todo =
  do jobs <- coreLift findCCJobs
     for_ [0 .. minus maxUnits 1] $ \k =>
       unless (k `elem` present) $
         do rm (unitObject u k)
            rm (unitSource u k)
            pure ()
     let objs = map (unitObject u) present
     if null todo
        then pure (Just objs)
        else do
          -- (the flags are found once: pkg-config may have to be run)
          cc <- coreLift findCC
          flags <- ccFlags
          let cmds = map (\(k, _) =>
                    let tmp = unitObject u k ++ ".tmp"
                        cmd = ccCommandWith cc flags ["-Werror", "-c"] u.asLib (unitSource u k) tmp
                    in (k, cmd ++ " && " ++ escapeCmd ["mv", "-f", tmp, unitObject u k]))
                    (sortBy (\a, b => compare (snd b) (snd a)) todo)
          -- A POSIX shell script: workers that take the units one by one
          -- (a unit is claimed by making a directory for it).
          let claims = concatMap (\(k, cmd) =>
                 "  if claim " ++ show k ++ "; then " ++ cmd
                    ++ " || { : > \"$d/failed\"; return 1; }; fi\n") cmds
          let workers = min jobs (length todo)
          let script = unlines
                [ "d=" ++ escapeCmd [u.baseName ++ ".claim"] ++ ".$$"
                , "rm -rf \"$d\"; mkdir \"$d\" || exit 1"
                , "claim() { [ ! -e \"$d/failed\" ] && mkdir \"$d/$1\" 2>/dev/null; }"
                , "worker() {"
                , claims ++ "  return 0"
                , "}"
                , "pids=; i=0"
                , "while [ $i -lt " ++ show workers ++ " ]; do worker & pids=\"$pids $!\"; i=$((i + 1)); done"
                , "s=0; for p in $pids; do wait $p || s=1; done"
                , "rm -rf \"$d\"; exit $s" ]
          let scriptFile = u.baseName ++ ".build.sh"
          Right () <- coreLift $ writeFile scriptFile script
            | Left err => throw $ FileErr scriptFile err
          log "compiler.refc.cc" 10 $ "Compiling " ++ show (length todo) ++ " units, see " ++ scriptFile
          0 <- coreLift $ system (escapeCmd ["sh", scriptFile])
            | _ => do for_ (map fst todo) $ \k => rm (unitObject u k ++ ".tmp")
                      pure Nothing
          pure (Just objs)

||| Link object files to `outFile`.
export
compileCFiles : {auto c : Ref Ctxt Defs}
             -> {default False asShared : Bool}
             -> (objectFiles : List String)
             -> (outFile : String)
             -> Core (Maybe String)
compileCFiles {asShared} objectFiles outFile =
  do cc <- coreLift findCC
     cFlags <- coreLift findCFLAGS
     ldFlags <- coreLift findLDFLAGS
     ldLibs <- coreLift findLDLIBS

     dirs <- getDirs
     refcDir <- findDataFile "refc"
     supportFile <- findLibraryFile "libidris2i_1_support.a"

     let sharedFlag = if asShared then ["-shared"] else []

     -- what the directives of the program link (see above)
     archives <- refcArchives
     libs <- refcLibs
     pkgConfig <- pkgConfigFlags "--libs"
     sections <- gcSections
     let gcFlag = if sections then "-Wl,--gc-sections " else ""

     let runcc = (escapeCmd $
         [cc, "-Werror"] ++ sharedFlag ++ objectFiles ++ archives
           ++ map ("-l" ++) libs)
           ++ " " ++ pkgConfig ++ " " ++ (escapeCmd $ [
              "-o", outFile,
              supportFile,
              "-lidris2i_1_refc",
              "-L" ++ refcDir
              ] ++ clibdirs (lib_dirs dirs) ++ [
              "-lgmp", "-lm", "-pthread"])
              ++ " " ++ gcFlag ++ (unwords [cFlags, ldFlags, ldLibs])

     log "compiler.refc.cc" 10 runcc
     0 <- coreLift $ system runcc
       | _ => pure Nothing

     pure (Just outFile)

export
compileCFile : {auto c : Ref Ctxt Defs}
            -> {default False asShared : Bool}
            -> (objectFile : String)
            -> (outFile : String)
            -> Core (Maybe String)
compileCFile {asShared} objectFile outFile
  = compileCFiles {asShared} [objectFile] outFile
