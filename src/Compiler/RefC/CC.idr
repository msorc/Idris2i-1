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

%default total

findCC : IO String
findCC
    = do Nothing <- idrisGetEnv "IDRIS2_CC"
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
  = do Nothing <- idrisGetEnv "IDRIS2_CFLAGS"
         | Just cflags => pure ("-O2 " ++ cflags)
       Nothing <- idrisGetEnv "CFLAGS"
         | Just cflags => pure ("-O2 " ++ cflags)
       pure "-O2"

findCPPFLAGS : IO String
findCPPFLAGS
  = do Nothing <- idrisGetEnv "IDRIS2_CPPFLAGS"
         | Just cppflags => pure cppflags
       Nothing <- idrisGetEnv "CPPFLAGS"
         | Just cppflags => pure cppflags
       pure ""

findLDFLAGS : IO String
findLDFLAGS
  = do Nothing <- idrisGetEnv "IDRIS2_LDFLAGS"
         | Just ldflags => pure ldflags
       Nothing <- idrisGetEnv "LDFLAGS"
         | Just ldflags => pure ldflags
       pure ""

findLDLIBS : IO String
findLDLIBS
  = do Nothing <- idrisGetEnv "IDRIS2_LDLIBS"
         | Just ldlibs => pure ldlibs
       Nothing <- idrisGetEnv "LDLIBS"
         | Just ldlibs => pure ldlibs
       pure ""

clibdirs : List String -> List String
clibdirs ds = map (\d => "-L" ++ d) ds

-- cincdirs : List String -> String
-- cincdirs ds = concat (map (\d => "-I" ++ d ++ " ") ds)

-- The command that compiles `sourceFile` to `objectFile`, with `extra` flags.
ccObjectCommand : {auto c : Ref Ctxt Defs}
               -> (asLibrary : Bool)
               -> (extra : List String)
               -> (sourceFile : String)
               -> (objectFile : String)
               -> Core String
ccObjectCommand asLibrary extra sourceFile objectFile =
  do cc <- coreLift findCC
     cFlags <- coreLift findCFLAGS
     cppFlags <- coreLift findCPPFLAGS

     refcDir <- findDataFile "refc"
     cDir <- findDataFile "c"

     let libraryFlag = if asLibrary then ["-fpic"] else []

     pure $ (escapeCmd $
         [cc, "-Werror", "-c"] ++ libraryFlag ++ extra ++ [sourceFile,
              "-o", objectFile,
              "-I" ++ refcDir,
              "-I" ++ cDir])
              ++ " " ++ cppFlags ++ " " ++ cFlags

export
compileCObjectFile : {auto c : Ref Ctxt Defs}
                  -> {default False asLibrary : Bool}
                  -> (sourceFile : String)
                  -> (objectFile : String)
                  -> Core (Maybe String)
compileCObjectFile {asLibrary} sourceFile objectFile =
  do runccobj <- ccObjectCommand asLibrary [] sourceFile objectFile
     log "compiler.refc.cc" 10 runccobj
     0 <- coreLift $ system runccobj
       | _ => pure Nothing

     pure (Just objectFile)

-- How many C compilers to run at once: IDRIS2_CC_JOBS, or the number of
-- processors.
findCCJobs : IO Nat
findCCJobs
  = do Just jobs <- idrisGetEnv "IDRIS2_CC_JOBS"
         | Nothing => map (fromMaybe 1) getNProcessors
       pure $ fromMaybe 1 $ parsePositive {a = Nat} jobs

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
  = do Just v <- run (cc ++ " --version 2>&1")
         | Nothing => pure Nothing
       Just m <- run (cc ++ " -dumpmachine 2>&1")
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

-- The variables, other than the flags, that a C compiler reads and that
-- change what it makes of a file.
ccEnvVars : List String
ccEnvVars = ["CPATH", "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "SDKROOT",
             "GCC_EXEC_PREFIX", "COMPILER_PATH", "LIBRARY_PATH",
             "SOURCE_DATE_EPOCH", "DEPENDENCIES_OUTPUT", "SUNPRO_DEPENDENCIES"]

||| Get the units of a program ready: find out whether the object files of the
||| last build may be reused, which is when they were made in the same
||| environment (the C compiler and its version, `IDRIS2_CC`, `IDRIS2_CFLAGS`,
||| `IDRIS2_CPPFLAGS`, `-fpic`, the include directories, the contents of the
||| headers of the runtime in the `refc` and `c` support directories, and
||| the variables that the compiler reads), and remove them when they were
||| not.  `headers` are the headers that the program includes: if one of them
||| is not in the support directories (so that its content is not known)
||| nothing is reused.
export
prepareUnits : {auto c : Ref Ctxt Defs}
            -> {default False asLibrary : Bool}
            -> (base : String)
            -> (headers : List String)
            -> Core Units
prepareUnits {asLibrary} base headers =
  do let units = MkUnits base asLibrary False
     cc <- coreLift findCC
     cmd <- ccObjectCommand asLibrary [] "UNIT.c" "UNIT.o"
     refcDir <- findDataFile "refc"
     cDir <- findDataFile "c"
     idt <- coreLift $ ccIdentity cc
     hs1 <- coreLift $ headerTexts refcDir
     hs2 <- coreLift $ headerTexts cDir
     envs <- coreLift $ traverse (\v => map (\x => v ++ "=" ++ fromMaybe "" x ++ "\n")
                                            (getEnv v)) ccEnvVars
     known <- coreLift $ traverse (\h => do a <- exists (refcDir ++ "/" ++ h)
                                            b <- exists (cDir ++ "/" ++ h)
                                            pure (a || b)) headers
     let key = (\i, a, b => unlines ["idris2 refc units 1", cmd, i, concat envs]
                             ++ concat a ++ concat b) <$> idt <*> hs1 <*> hs2
     case key of
          Just k => if all id known
                       then do old <- coreLift $ readFile (keyFile units)
                               unless (either (const False) (== k) old) $
                                 do removeObjs units
                                    _ <- coreLift $ writeFile (keyFile units) k
                                    pure ()
                               pure ({ reuseObjs := True } units)
                       else noReuse units
          Nothing => noReuse units
  where
    removeObjs : Units -> Core ()
    removeObjs u = for_ [0 .. minus maxUnits 1] $ \k => rm (unitObject u k)
    noReuse : Units -> Core Units
    noReuse u = do removeObjs u
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
||| sizes), the biggest first, with at most IDRIS2_CC_JOBS (the number of
||| processors) C compilers running at once.  `present` are the units of the
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
          cmds <- traverse (\(k, _) => do
                    let tmp = unitObject u k ++ ".tmp"
                    cmd <- ccObjectCommand u.asLib [] (unitSource u k) tmp
                    pure (k, cmd ++ " && " ++ escapeCmd ["mv", "-f", tmp, unitObject u k]))
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
     supportFile <- findLibraryFile "libidris2_support.a"

     let sharedFlag = if asShared then ["-shared"] else []

     let runcc = (escapeCmd $
         [cc, "-Werror"] ++ sharedFlag ++ objectFiles ++ [
              "-o", outFile,
              supportFile,
              "-lidris2_refc",
              "-L" ++ refcDir
              ] ++ clibdirs (lib_dirs dirs) ++ [
              "-lgmp", "-lm", "-pthread"])
              ++ " " ++ (unwords [cFlags, ldFlags, ldLibs])

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
