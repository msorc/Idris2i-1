module Compiler.RefC.CC

import Core.Context.Log
import Core.Options
import Core.Directory

import System
import System.Info
import Idris.Env

import Data.String

%default total

findCC : IO String
findCC
    = do Nothing <- idrisGetEnv "IDRIS2_CC"
           | Just cc => pure cc
         Nothing <- idrisGetEnv "CC"
           | Just cc => pure cc
         pure "cc"

findCFLAGS : IO String
findCFLAGS
  = do Nothing <- idrisGetEnv "IDRIS2_CFLAGS"
         | Just cflags => pure cflags
       Nothing <- idrisGetEnv "CFLAGS"
         | Just cflags => pure cflags
       -- Without optimisation, the inline functions of the runtime (reference
       -- counting, allocation) are not inlined, which makes the code several
       -- times slower.
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

||| Compile a C file that generateCSourceFileParts wrote in `chunks` chunks
||| (0 when it is not split): split ones are compiled in parts, by C compilers
||| running in parallel.  Returns the object files.
export
compileCObjectFiles : {auto c : Ref Ctxt Defs}
                   -> {default False asLibrary : Bool}
                   -> (chunks : Nat)
                   -> (sourceFile : String)
                   -> (objectFile : String)
                   -> Core (Maybe (List String))
compileCObjectFiles {asLibrary} chunks sourceFile objectFile =
  do jobs <- coreLift findCCJobs
     let parts = min jobs chunks
     -- The parallel compile is a POSIX shell script.
     if parts <= 1 || isWindows
        then map (\o => [o]) <$> compileCObjectFile {asLibrary} sourceFile objectFile
        else do
          let base = if ".o" `isSuffixOf` objectFile
                        then substr 0 (length objectFile `minus` 2) objectFile
                        else objectFile
          let objs = map (\i => base ++ "." ++ show i ++ ".o") [0 .. parts `minus` 1]
          cmds <- traverse (\(i, o) =>
                      ccObjectCommand asLibrary
                        ["-DIDRIS2_PARTS=" ++ show parts, "-DIDRIS2_PART=" ++ show i]
                        sourceFile o)
                    (zip [0 .. parts `minus` 1] objs)
          let script = concatMap (\cmd => cmd ++ " & pids=\"$pids $!\"; ") cmds
                       ++ "s=0; for p in $pids; do wait $p || s=1; done; exit $s"
          log "compiler.refc.cc" 10 script
          0 <- coreLift $ system ("pids=; " ++ script)
            | _ => pure Nothing
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
