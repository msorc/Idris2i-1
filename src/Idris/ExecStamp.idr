||| Telling whether the executable of a package, built by an earlier
||| `idris2 --build`, is certainly up to date.
|||
||| Compiling an executable is a whole-program compilation: it takes the
||| same time whether or not any module changed.  After it succeeds, a stamp
||| file is written next to the executable.  It lists what the executable
||| was made from (the TTC files of the program, the compiler itself, the
||| runtime support files, ...) and the state those files had, together with
||| the settings of the compilation.  The next build skips the compilation
||| when all of that is exactly as the stamp says, and the executable is
||| still the one that was built.  Whenever in doubt (a file cannot be
||| inspected, a backend is not known to be handled, ...) there is no stamp,
||| or it does not match, and the executable is compiled again.
|||
||| The state of a file is its modification time (to the nanosecond, where
||| the file system keeps it) and its size.
module Idris.ExecStamp

import Compiler.RefC.CC

import Core.Context
import Core.Context.Log
import Core.Core
import Core.Directory
import Core.Options

import Data.List
import Data.Maybe
import Data.String

import Idris.Env

import IdrisPaths

import Libraries.Utils.Path

import System
import System.Clock
import System.Directory
import System.File
import System.Info

%default covering

--------------------------------------------------------------------------------
-- The state of files

||| Modification time and size
record Stat where
  constructor MkStat
  sec : Int
  nsec : Int
  size : Int

showStat : Maybe Stat -> String
showStat Nothing = "missing"
showStat (Just st) = "\{show st.sec}.\{show st.nsec}/\{show st.size}"

||| The last time a file was modified, in nanoseconds, rounded up when the
||| file system keeps seconds only.
latest : Maybe Stat -> Integer
latest Nothing = 0
latest (Just st)
    = let s = cast {to = Integer} st.sec * 1000000000
          ns = cast {to = Integer} st.nsec
      in if st.nsec == 0 then s + 1000000000 else s + ns

statOf : String -> IO (Maybe Stat)
statOf file
    = do Right h <- openFile file Read
           | Left _ => pure Nothing
         Right t <- fileTime h
           | Left _ => do closeFile h
                          pure Nothing
         Right size <- fileSize h
           | Left _ => do closeFile h
                          pure Nothing
         closeFile h
         pure (Just (MkStat t.mtime.sec t.mtime.nsec size))

||| Is this a script (a launcher) rather than a binary?
isScript : String -> IO Bool
isScript file
    = do Right h <- openFile file Read
           | Left _ => pure False
         Right start <- fGetChars h 2
           | Left _ => do closeFile h
                          pure False
         closeFile h
         pure (start == "#!")

--------------------------------------------------------------------------------
-- What the executable is made from

||| A thing that the executable depends on (or is)
public export
data Item : Type where
  ||| A TTC file that goes into the program: the module, where it was found
  TTCFile : (mod : ModuleIdent) -> (file : String) -> Item
  ||| A file that must not change
  Input : (file : String) -> Item
  ||| A directory, whose content must not change
  InDir : (dir : String) -> Item
  ||| A directory where libraries are looked for: what must not change is its
  ||| libraries (shared or static), not the other files that may be there
  LibDir : (dir : String) -> Item
  ||| A file that the compilation writes, and that must be as it was left
  Output : (file : String) -> Item
  ||| The binary that a RefC compilation writes.  The Makefile of the
  ||| compiler moves it, to the second path, and puts a launcher in its
  ||| place: it is the binary, at either place, that must be as it was left.
  Binary : (file, moved : String) -> Item

-- Does the name of a file look like the one of a library?
isLibrary : String -> Bool
isLibrary n = isInfixOf ".so" n || isSuffixOf ".a" n || isSuffixOf ".dylib" n
              || isSuffixOf ".dll" n || isSuffixOf ".lib" n

-- The names of the files of a directory (those that `keep` says), and
-- their state
fingerprintDir : {auto c : Ref Ctxt Defs} ->
                 (tag : String) -> (keep : String -> Bool) -> (dir : String) ->
                 Core (List String, Integer)
fingerprintDir tag keep dir
    = do Right names <- coreLift $ listDir dir
           | Left _ => pure (["\{tag} \{dir} missing"], 0)
         let names = sort (filter (\n => n /= "." && n /= ".." && keep n) names)
         sts <- traverse (\n => coreLift $ statOf (dir </> n)) names
         pure ( "\{tag} \{dir}" ::
                  zipWith (\n, st => "  \{n} \{showStat st}") names sts
              , foldl max 0 (map latest sts))

||| The lines that tell the state of an item, and the time when its newest
||| input was written (0 for the outputs)
fingerprintItem : {auto c : Ref Ctxt Defs} -> Item -> Core (List String, Integer)
fingerprintItem (TTCFile mod file)
    = do Right found <- nsToPath emptyFC mod
           | Left _ => pure (["ttc \{show mod} not found"], 0)
         if found /= file
            then pure (["ttc \{show mod} found at \{found}"], 0)
            else do st <- coreLift $ statOf file
                    pure (["ttc \{show mod} \{showStat st}"], latest st)
fingerprintItem (Input file)
    = do st <- coreLift $ statOf file
         pure (["in \{file} \{showStat st}"], latest st)
fingerprintItem (InDir dir) = fingerprintDir "dir" (\n => True) dir
fingerprintItem (LibDir dir) = fingerprintDir "libdir" isLibrary dir
fingerprintItem (Output file)
    = do st <- coreLift $ statOf file
         pure (["out \{file} \{showStat st}"], 0)
fingerprintItem (Binary file moved)
    = do script <- coreLift $ isScript file
         st <- coreLift $ statOf (if script then moved else file)
         pure (["bin \{showStat st}"], 0)

||| What a stamp file records of an item.  The paths are separated by tabs.
renderItem : Item -> Maybe String
renderItem item = case fields item of
                       (tag, args) =>
                         if any (any (\c => c == '\t' || c == '\n') . unpack) args
                            then Nothing
                            else Just (joinBy "\t" (tag :: args))
  where
    fields : Item -> (String, List String)
    fields (TTCFile mod file) = ("ttc", [show mod, file])
    fields (Input file) = ("in", [file])
    fields (InDir dir) = ("dir", [dir])
    fields (LibDir dir) = ("libdir", [dir])
    fields (Output file) = ("out", [file])
    fields (Binary file moved) = ("bin", [file, moved])

splitOn : Char -> String -> List String
splitOn c s
    = case break (== c) (unpack s) of
           (a, []) => [pack a]
           (a, _ :: rest) => pack a :: splitOn c (pack rest)

parseItem : String -> Maybe Item
parseItem line
    = case splitOn '\t' line of
           ["ttc", mod, file] =>
              Just (TTCFile (unsafeFoldModuleIdent (reverse (splitOn '.' mod))) file)
           ["in", file] => Just (Input file)
           ["dir", dir] => Just (InDir dir)
           ["libdir", dir] => Just (LibDir dir)
           ["out", file] => Just (Output file)
           ["bin", file, moved] => Just (Binary file moved)
           _ => Nothing

||| The state of all the items, and the time when the newest input was
||| written
fingerprint : {auto c : Ref Ctxt Defs} -> List Item -> Core (List String, Integer)
fingerprint items
    = do fs <- traverse fingerprintItem items
         pure (concatMap fst fs, foldl max 0 (map snd fs))

--------------------------------------------------------------------------------
-- The settings of the compilation

-- The environment variables that RefC reads (see Compiler.RefC.CC), and
-- those that the C compiler reads
refcEnv : List String
refcEnv = [ "IDRIS2_CC", "CC", "IDRIS2_CFLAGS", "CFLAGS"
          , "IDRIS2_CPPFLAGS", "CPPFLAGS", "IDRIS2_LDFLAGS", "LDFLAGS"
          , "IDRIS2_LDLIBS", "LDLIBS", "IDRIS2_REFC_SPLIT_SIZE" ]
          ++ ccEnvVars

envLine : String -> IO String
envLine name
    = do val <- getEnv name
         pure ("env \{name} " ++ maybe "unset" show val)

||| The file of a program (a path, or a name looked for in the `PATH`), as
||| the backends run it (as a single word: `IDRIS2_CC`, `CC` and `CHEZ` are
||| programs, not command lines)
programOf : String -> IO (Maybe String)
programOf p = if '/' `elem` unpack p
                 then pure (Just p)
                 else pathLookup [p]

-- Compiler.Scheme.Chez.findChez, which this module cannot import
findChez : IO String
findChez = do Nothing <- idrisGetEnv "CHEZ"
                | Just chez => pure chez
              path <- pathLookup ["chez", "chezscheme", "chez-scheme", "chezscheme9.5", "scheme"]
              pure $ fromMaybe "/usr/bin/env scheme" path

||| The file of the tool that compiles the program for the backend (the C
||| compiler, Chez Scheme), as it is found now
toolOf : CG -> IO (Maybe String)
toolOf RefC = findCC >>= programOf
toolOf _ = findChez >>= programOf

-- The backends whose executables are handled
handled : CG -> Bool
handled RefC = True
handled Chez = True
handled _ = False

||| The settings of the compilation that are not about files: if there
||| are none, the executable is not handled (it is compiled every time).
settings : {auto c : Ref Ctxt Defs} ->
           (mainNS : ModuleIdent) -> (mainFile : String) ->
           Core (Maybe (List String))
settings mainNS mainFile
    = do defs <- get Ctxt
         let opts = options defs
         let sess = session opts
         let d = dirs opts
         let cg = codegen sess
         let inc = not (wholeProgram sess) && (cg `elem` incrementalCGs sess)
         let dumpFiles : List (Maybe String)
               = [dumpcases sess, dumplifted sess, dumpanf sess, dumpvmcode sess]
         let dumps = any isJust dumpFiles
         wd <- getWorkingDir
         if isWindows || inc || dumps || not (handled cg)
            then pure Nothing
            else do
              envs <- case cg of
                           RefC => coreLift $ traverse envLine refcEnv
                           _ => coreLift $ traverse envLine ["CHEZ"]
              -- The tool as it is found now: the stamp lists the file that
              -- was found when it was written, whose state it checks, but
              -- another one may be found now (the `PATH` changed, or a
              -- program was put in a directory that comes earlier in it).
              tool <- coreLift $ toolOf cg
              pure $ Just $
                [ "idris2 \{show idrisVersion}"
                , "cwd \{show wd}"
                , "codegen \{show cg}"
                , "main \{show (show mainNS)} \{show mainFile}"
                , "directives \{show (directives sess)}"
                , "profile \{show (profile sess)}"
                , "nocse \{show (noCSE sess)}"
                , "specinterfaces \{show (specInterfaces sess)}"
                , "casetreeheuristics \{show (caseTreeHeuristics sess)}"
                , "totalreq \{show (totalReq sess)}"
                , "noprelude \{show (noprelude sess)}"
                , "debugelabcheck \{show (debugElabCheck sess)}"
                , "debugspeccollide \{show (debugSpecCollide sess)}"
                , "wholeprogram \{show (wholeProgram sess)}"
                , "incremental \{show (map show (incrementalCGs sess))}"
                , "build_dir \{show (build_dir d)}"
                , "output_dir \{show (outputDirWithDefault d)}"
                , "depends_dir \{show (depends_dir d)}"
                , "prefix_dir \{show (prefix_dir d)}"
                , "extra_dirs \{show (extra_dirs d)}"
                , "package_dirs \{show (package_dirs d)}"
                , "lib_dirs \{show (lib_dirs d)}"
                , "data_dirs \{show (data_dirs d)}"
                , "tool \{show tool}"
                ] ++ envs

-- The directories of `-L` options in a list of flags
libFlagDirs : List String -> List String
libFlagDirs ("-L" :: dir :: rest) = dir :: libFlagDirs rest
libFlagDirs (flag :: rest)
    = if "-L" `isPrefixOf` flag
         then substr 2 (length flag) flag :: libFlagDirs rest
         else libFlagDirs rest
libFlagDirs [] = []

||| The things that the executable is made from, that are not the TTC files
||| of the program: the compiler, the runtime support, the tools it uses,
||| the headers and libraries of the program
inputs : {auto c : Ref Ctxt Defs} -> (exec : String) -> Core (Maybe (List Item))
inputs exec
    = do d <- getDirs
         args <- coreLift getArgs
         -- The compiler: the binary of the process, and the program that was
         -- started (which is what holds the compiler, when the binary is the
         -- interpreter of a Scheme program).
         procExe <- coreLift $ exists "/proc/self/exe"
         let selfExe : List Item = if procExe then [Input "/proc/self/exe"] else []
         let selfArg : List Item
               = case args of
                      (a :: _) => if isAbsolute a then [Input a] else []
                      [] => []
         let cg = codegen !getSession
         -- the directories where the C compiler looks for libraries, other
         -- than its own ones
         ccLibs <- case cg of
                        RefC => do ldflags <- coreLift findLDFLAGS
                                   path <- coreLift $ getEnv "LIBRARY_PATH"
                                   pure (libFlagDirs (words ldflags)
                                         ++ maybe [] (filter (/= "") . splitOn ':') path)
                        _ => pure []
         let libs = lib_dirs d ++ map (</> "lib") (package_dirs d ++ extra_dirs d)
                      ++ ccLibs
         let libItems = map LibDir libs
         let supportDirs = case cg of
                                RefC => ["refc", "c"]
                                _ => ["chez"]
         supports <- traverse (\s => catch (Just <$> findDataFile s)
                                           (\_ => pure Nothing))
                              supportDirs
         tool <- coreLift $ toolOf cg
         -- the headers that the C file of a RefC program includes, besides
         -- those of the runtime (see Compiler.RefC.CC.headerDepsFile)
         headers <- case cg of
                         RefC => coreLift $ headerItems
                                   (headerDepsFile (outputDirWithDefault d </> exec))
                         _ => pure (Just [])
         let toolItems : List Item = maybe [] (\t => [Input t]) tool
         -- the files that `--directive extraRuntime=file` includes
         let extraItems : List Item
               = mapMaybe extraRuntime (directives !getSession)
         let supportItems : List Item = map InDir (catMaybes supports)
         pure $ if null selfExe && null selfArg || any isNothing supports
                   then Nothing
                   else map (\hs => selfExe ++ selfArg ++ supportItems
                                      ++ libItems ++ toolItems ++ extraItems ++ hs)
                            headers
  where
    -- Nothing when the files are not known
    headerItems : String -> IO (Maybe (List Item))
    headerItems file
        = do True <- exists file
               | False => pure (Just [])
             Right txt <- readFile file
               | Left _ => pure Nothing
             pure $ case lines txt of
                         (l :: files) => if l == headerDepsLine
                                            then Just (map Input files)
                                            else Nothing
                         [] => Nothing

    extraRuntime : String -> Maybe Item
    extraRuntime d
        = let (k, v) = break (== '=') d
          in if trim k == "extraRuntime" then Just (Input (trim (substr 1 (length v) v)))
                                         else Nothing


||| What the compilation writes
outputs : {auto c : Ref Ctxt Defs} -> (exec : String) -> Core (List Item)
outputs exec
    = do d <- getDirs
         let out = outputDirWithDefault d
         let app = out </> (exec ++ "_app")
         pure $ case codegen !getSession of
                     RefC => [Binary (out </> exec) (app </> exec)]
                     _ => [ Output (out </> exec)
                          , Output (app </> exec <.> "so")
                          , Output (app </> exec <.> "ss") ]

stampFile : {auto c : Ref Ctxt Defs} -> (exec : String) -> Core String
stampFile exec
    = do d <- getDirs
         pure (outputDirWithDefault d </> (exec ++ ".stamp"))

stampHeader : String
stampHeader = "idris2 executable stamp 2"

--------------------------------------------------------------------------------
-- Writing and checking the stamp

||| Remove the stamp of an executable, before compiling it again.
export
removeStamp : {auto c : Ref Ctxt Defs} -> (exec : String) -> Core ()
removeStamp exec
    = do stamp <- stampFile exec
         _ <- coreLift $ removeFile stamp
         pure ()

-- A file system may report a time of modification a little earlier than the
-- clock does (the clock of the kernel that dates the files ticks, rather than
-- running): a file written within this many nanoseconds before a time may be
-- told as written after it.
margin : Integer
margin = 30000000

||| The time when the compilation starts, to tell later whether files were
||| written during it (and may have been read before).  It is taken once the
||| files that the build wrote are certainly dated before it: they are not
||| mistaken for files that changed during the compilation.
export
compilationStart : Core Integer
compilationStart
    = do coreLift $ usleep 50000
         t <- coreLift $ clockTime UTC
         pure (seconds t * 1000000000 + nanoseconds t)

||| Write the stamp of the executable that was just compiled (successfully,
||| from the main module `mainNS`, in `mainFile`), if that can be done
||| reliably.  `started` is the time when the compilation started (see
||| `compilationStart`).
export
writeStamp : {auto c : Ref Ctxt Defs} ->
             (exec : String) -> (mainNS : ModuleIdent) -> (mainFile : String) ->
             (started : Integer) -> Core ()
writeStamp exec mainNS mainFile started
    = do Just sets <- settings mainNS mainFile
           | Nothing => pure ()
         Just ins <- inputs exec
           | Nothing => log "package.stamp" 5 "No stamp: what the executable is made from is not known"
         defs <- get Ctxt
         mainTTC <- getTTCFileName mainFile "ttc"
         mainMod <- ctxtPathToNS mainFile
         let loaded = (mainTTC, mainMod) ::
                      map (\(file, (mod, _, _)) => (file, mod)) (allImported defs)
         let ttcs = map (\(file, mod) => TTCFile mod file)
                        (nubBy (\x, y => fst x == fst y) loaded)
         outs <- outputs exec
         let items = ttcs ++ ins ++ outs
         Just spec <- pure $ traverse renderItem items
           | Nothing => pure ()
         -- Files that were written since the compilation started (or may
         -- have been, see `margin`) may have been read before.
         (fp, newest) <- fingerprint items
         if newest + margin >= started
            then log "package.stamp" 5 "No stamp: files were written during the compilation"
            else do
              stamp <- stampFile exec
              Right () <- coreLift $ writeFile stamp $ unlines $
                            [stampHeader] ++ spec ++ ["---"] ++ sets ++ fp ++ ["end"]
                | Left err => log "package.stamp" 5 "No stamp: \{show err}"
              log "package.stamp" 5 "Wrote \{stamp}"

||| Is the executable, as it was left by the last build that wrote a stamp,
||| certainly what compiling it now (from the main module `mainNS`, in
||| `mainFile`) would make?
export
upToDate : {auto c : Ref Ctxt Defs} ->
           (exec : String) -> (mainNS : ModuleIdent) -> (mainFile : String) ->
           Core Bool
upToDate exec mainNS mainFile
    = do Just sets <- settings mainNS mainFile
           | Nothing => no "this backend or these options are not handled"
         stamp <- stampFile exec
         Right content <- coreLift $ readFile stamp
           | Left _ => no "there is no stamp"
         let (header :: rest) = lines content
           | [] => no "the stamp is empty"
         if header /= stampHeader then no "the stamp is of another format" else do
           let (spec, rest) = break (== "---") rest
           let (recorded, end) = break (== "end") (drop 1 rest)
           if end /= ["end"] then no "the stamp is cut short" else do
             Just items <- pure $ traverse parseItem spec
               | Nothing => no "the stamp cannot be read"
             (fp, _) <- fingerprint items
             if sets ++ fp == recorded
                then pure True
                else do
                  log "package.stamp" 10 $ unlines $
                    "The stamp differs on:" ::
                      filter (\l => not (l `elem` recorded)) (sets ++ fp)
                  no "something it was made from changed"
  where
    no : String -> Core Bool
    no why = do log "package.stamp" 5 "Compiling the executable: \{why}"
                pure False
