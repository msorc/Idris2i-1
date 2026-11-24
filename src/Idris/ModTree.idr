module Idris.ModTree

import Core.Binary
import Core.Directory
import Core.Metadata
import Core.InitPrimitives
import Core.UnifyState

import Idris.Parser
import Idris.ProcessIdr
import Idris.REPL.Common
import Idris.Syntax
import Idris.Pretty

import Data.Either
import Data.List
import Data.SortedMap
import Data.SortedSet
import Data.String

import System
import System.Directory
import System.File

import Libraries.Data.StringMap
import Libraries.Utils.Path

%default covering

record ModTree where
  constructor MkModTree
  nspace : ModuleIdent
  sourceFile : Maybe String
  deps : List ModTree

covering
Show ModTree where
  show t = show (sourceFile t) ++ " " ++ show (nspace t) ++ "<-" ++ show (deps t)

-- A module file to build, and its list of dependencies
-- From this we can work out if the source file needs rebuilding, assuming
-- things are build in dependency order. A source file needs rebuilding
-- if:
--  + Its corresponding ttc is older than the source file
--  + Any of the import ttcs are *newer* than the corresponding ttc
--    (If so: also any imported ttc's fingerprint is different from the one
--    stored in the source file's ttc)
public export
record BuildMod where
  constructor MkBuildMod
  buildFile : String
  buildNS : ModuleIdent
  imports : List ModuleIdent

export
Show BuildMod where
  show t = buildFile t ++ " [" ++ showSep ", " (map show (imports t)) ++ "]"

data AllMods : Type where

mkModTree : {auto c : Ref Ctxt Defs} ->
            {auto o : Ref ROpts REPLOpts} ->
            {auto a : Ref AllMods (List (ModuleIdent, ModTree))} ->
            FC ->
            (done : List ModuleIdent) -> -- if 'mod' is here we have a cycle
            (modFP : Maybe FileName) -> -- Sometimes we know already know what the file name is
            (mod : ModuleIdent) ->      -- Otherwise we'll compute it from the module name
            Core ModTree
mkModTree loc done modFP mod
  = if mod `elem` done
       then throw (CyclicImports (done ++ [mod]))
       else
          -- Read imports from source file. If the source file isn't
          -- available, it's not our responsibility
          catch (do all <- get AllMods
                    -- If we've seen it before, reuse what we found
                    case lookup mod all of
                         Nothing =>
                           do file <- maybe (nsToSource loc mod) pure modFP
                              imps <- readHeaderImports file mod
                              if mod `elem` imps
                                then coreFail $ CyclicImports [mod, mod]
                                else do
                                  ms <- traverse (mkModTree loc (mod :: done) Nothing) imps
                                  let mt = MkModTree mod (Just file) ms
                                  update AllMods ((mod, mt) ::)
                                  pure mt
                         Just m => pure m)
                -- Couldn't find source, assume it's in a package directory
                (\err =>
                    case err of
                         CyclicImports {} => throw err
                         ParseFail {} => throw err
                         LexFail {} => throw err
                         LitFail {} => throw err
                         _ => pure (MkModTree mod Nothing []))

data DoneMod : Type where
data BuildOrder : Type where
data TTCPaths : Type where
data RunningJobs : Type where

-- Given a module tree, returns the modules in the reverse order they need to
-- be built, including their dependencies
mkBuildMods : {auto d : Ref DoneMod (StringMap ())} ->
              {auto o : Ref BuildOrder (List BuildMod)} ->
              ModTree -> Core ()
mkBuildMods mod
    = whenJust (sourceFile mod) $ \ sf =>
            do done <- get DoneMod
               case lookup sf done of
                    Just _ => pure ()
                    Nothing =>
                       do -- build dependencies
                          traverse_ mkBuildMods (deps mod)
                          -- build it now
                          update BuildOrder
                                   (MkBuildMod sf mod.nspace
                                               (map nspace mod.deps) ::)
                          update DoneMod $ insert sf ()

-- Given a main file name, return the list of modules that need to be
-- built for that main file, in the order they need to be built
-- Return an empty list if it turns out it's in the 'done' list
-- (The module trees in AllMods are those already read, from the headers of
-- the source files.)
getBuildModsWith : {auto c : Ref Ctxt Defs} ->
                   {auto o : Ref ROpts REPLOpts} ->
                   Ref AllMods (List (ModuleIdent, ModTree)) ->
                   FC -> (done : List BuildMod) ->
                   (mainFile : String) ->
                   Core (List BuildMod)
getBuildModsWith a loc done fname
    = do fname_ns <- ctxtPathToNS fname
         if fname_ns `elem` map buildNS done
            then pure []
            else
              do t <- mkModTree {a} loc [] (Just fname) fname_ns
                 dm <- newRef DoneMod empty
                 o <- newRef BuildOrder []
                 mkBuildMods {d=dm} {o} t
                 pure (reverse !(get BuildOrder))

export
getBuildMods : {auto c : Ref Ctxt Defs} ->
               {auto o : Ref ROpts REPLOpts} ->
               FC -> (done : List BuildMod) ->
               (mainFile : String) ->
               Core (List BuildMod)
getBuildMods loc done fname
    = do a <- newRef AllMods []
         getBuildModsWith a loc done fname

checkTotalReq : {auto c : Ref Ctxt Defs} ->
                String -> String -> TotalReq -> Core Bool
checkTotalReq sourceFile ttcFile expected
  = catch (do log "totality.requirement" 20 $
                "Reading totalReq from " ++ ttcFile
              Just got <- readTotalReq ttcFile
                | Nothing => pure False
              log "totality.requirement" 20 $ unwords
                [ "Got", show got, "and expected", show expected ++ ":"
                , "we", ifThenElse (got < expected) "should" "shouldn't"
                , "rebuild" ]
              -- if what we got (i.e. what we used when we checked the file the
              -- first time around) was strictly less stringent than what we
              -- expect now then we need to rebuild.
              pure (got < expected))
          (\error => pure False)

-- The interface hashes of the TTC files of the modules that a build imports,
-- each read once: most modules import the same ones. The hash of a module
-- that is built changes, so it is forgotten when the module is built (and it
-- is read only after the module is up to date, as a module is looked at once
-- its imports are built).
export
data IfaceHashes : Type where

export
initIfaceHashes : Core (Ref IfaceHashes (SortedMap ModuleIdent Int))
initIfaceHashes = newRef IfaceHashes empty

forgetIfaceHash : {auto h : Ref IfaceHashes (SortedMap ModuleIdent Int)} ->
                  ModuleIdent -> Core ()
forgetIfaceHash ns = update IfaceHashes (delete ns)

-- The interface hash of the TTC file of an import, as `processMod` reads it,
-- or Nothing if there is no such file
importIfaceHash : {auto c : Ref Ctxt Defs} ->
                  {auto h : Ref IfaceHashes (SortedMap ModuleIdent Int)} ->
                  ModuleIdent -> Core (Maybe Int)
importIfaceHash ns
    = case lookup ns !(get IfaceHashes) of
           Just hash => pure (Just hash)
           Nothing =>
             do Right ttcFile <- nsToPath EmptyFC ns
                  | Left _ => pure Nothing
                (_, hash) <- readHashes ttcFile
                update IfaceHashes (insert ns hash)
                pure (Just hash)

-- Whether `processMod` would skip a module whose source file is older than
-- its TTC file, but some of whose imports were written after it: when the
-- interfaces of the imports did not change (see `unchangedModule`). The
-- imports are those that the TTC file recorded, which are those of the
-- source file when the key of the source file is the one it recorded; the
-- interface hashes it recorded are in the same order, after the prelude when
-- the prelude is imported implicitly, and tell the namespaces the imports
-- are imported as. Otherwise (as for a literate file) the module is built.
importsUnchanged : {auto c : Ref Ctxt Defs} ->
                   {auto h : Ref IfaceHashes (SortedMap ModuleIdent Int)} ->
                   (sourceFile, ttcFile : String) -> (origin : ModuleIdent) ->
                   Core Bool
importsUnchanged sourceFile ttcFile origin
    = do Just (key, _) <- sourceKey sourceFile
           | Nothing => pure False
         Just (key', imps) <- readSourceHeader ttcFile
           | Nothing => pure False
         let True = key == key'
           | False => pure False
         session <- getSession
         -- as processMod adds the prelude (a module whose header names
         -- another module than `origin` does not get this far)
         let preludeMod = nsAsModuleIdent preludeNS
         let allImps = if session.noprelude || origin == preludeMod
                             || elem preludeMod imps
                          then imps
                          else preludeMod :: imps
         stored <- readImportHashes ttcFile
         let True = length stored == length allImps
           | False => pure False
         Just hashes <- sequence <$> traverse importIfaceHash allImps
           | Nothing => pure False
         unchangedModule ttcFile True (zipWith (\(ns, _), hash => (ns, hash)) stored hashes)

needsBuildingTime : {auto c : Ref Ctxt Defs} ->
                    {auto h : Ref IfaceHashes (SortedMap ModuleIdent Int)} ->
                    (sourceFile : String) -> (ttcFile : String) ->
                    (origin : ModuleIdent) -> (depFiles : List String) -> Core Bool
needsBuildingTime sourceFile ttcFile origin depFiles
  = do True <- isTTCOutdated ttcFile (sourceFile :: depFiles)
         | False => pure False
       -- a source file that was written again is built again, as
       -- processMod does (it does not look at its content)
       False <- isTTCOutdated ttcFile [sourceFile]
         | True => pure True
       -- only imports were written again: if none has another interface,
       -- processMod would skip the module, so there is no need to start it
       unchanged <- importsUnchanged sourceFile ttcFile origin
       when unchanged $
         log "import" 10 $ "Imports of " ++ sourceFile ++ " are newer, with the same interfaces"
       pure (not unchanged)

needsBuildingDepHash : {auto c : Ref Ctxt Defs} ->
                 String -> Core Bool
needsBuildingDepHash depFileName
  = catch (do defs                   <- get Ctxt
              depTTCFileName         <- getTTCFileName depFileName "ttc"
              not <$> unchangedHash defs.options.hashFn depTTCFileName depFileName)
          (\error => pure False)

||| Build from source if any of the dependencies, or the associated source file,
||| have been modified from the stored hashes.
needsBuildingHash : {auto c : Ref Ctxt Defs} ->
                    (sourceFile : String) -> (ttcFile : String) ->
                    (origin : ModuleIdent) -> (depFiles : List String) -> Core Bool
needsBuildingHash sourceFile ttcFile origin depFiles
  = do defs                <- get Ctxt
       sourceUnchanged <- unchangedHash defs.options.hashFn ttcFile sourceFile
       depFilesHashDiffers <- any id <$> traverse needsBuildingDepHash depFiles
       pure $ (not sourceUnchanged) || depFilesHashDiffers

export
needsBuilding :
  {auto c : Ref Ctxt Defs} ->
  {auto o : Ref ROpts REPLOpts} ->
  {auto h : Ref IfaceHashes (SortedMap ModuleIdent Int)} ->
  (sourceFile, ttcFile : String) -> (origin : ModuleIdent) -> List String -> Core Bool
needsBuilding sourceFile ttcFile origin depFiles
  = do -- if the ttc file does not exist there is no point in asking
       -- whether we need to rebuild it
       True <- coreLift $ exists ttcFile
         | False => pure True
       -- a TTC written by another compiler may hold choices that this one
       -- would make differently (or not understand), so rebuild it
       True <- builtByThisCompiler ttcFile
         | False => do log "import" 20 $ ttcFile ++ " was written by another compiler"
                       pure True
       -- check if hash match
       checkHashesInsteadOfTime <- checkHashesInsteadOfModTime <$> getSession
       False <- ifThenElse checkHashesInsteadOfTime
                           needsBuildingHash
                           needsBuildingTime
                  sourceFile ttcFile origin depFiles
         | True => pure True

       log "import" 20 $ "\{ifThenElse checkHashesInsteadOfTime "Hashes" "Mod Times"} still valid for " ++ sourceFile

       False <- missingIncremental ttcFile
         | True => pure True

       -- in case we're loading the main file, make sure the TTC is
       -- using the appropriate default totality requirement
       Just f <- mainfile <$> get ROpts
         | Nothing => pure False
       log "totality.requirement" 10 $ concat {t = List}
         [ "Checking totality requirement of "
         , sourceFile
         , " (main file is "
         , f
         , ")"
         ]
       let True = sourceFile == f
         | False => pure False
       True <- checkTotalReq sourceFile ttcFile !(totalReq <$> getSession)
         | False => pure False
       -- if it needs rebuilding then remove the buggy .ttc file to avoid going
       -- into an infinite loop!
       Right () <- coreLift $ removeFile ttcFile
         | Left err => throw (FileErr ttcFile err)
       pure True

-- "num/len: Building Mod (file)", without "Building"
buildMessage : Nat -> Nat -> BuildMod -> (Doc IdrisAnn, Doc IdrisAnn)
buildMessage num len mod
    = let pad = minus (length $ show len) (length $ show num) in
      (pretty0 (replicate pad ' ') <+> byShow num <+> slash <+> byShow len <+> colon,
       pretty0 mod.buildNS <++> parens (pretty0 mod.buildFile))

-- Forget what the context holds, and what the previous module set
-- (%language, %pair, ...): each module is built as by a process of its own,
-- which is how a parallel build (buildAllParallel) builds it.
resetForModule : {auto c : Ref Ctxt Defs} ->
                 {auto s : Ref Syn SyntaxInfo} ->
                 Core ()
resetForModule
   = do clearCtxt; update Ctxt { options $= clearNames }; addPrimitives
        lazyActive True; setUnboundImplicits True
        put Syn initSyntax

-- Build a module if it is not up to date. The context is reset before the
-- module is built, but not when it is up to date: deciding that only takes
-- the options, and resetting the context (with the primitives added again)
-- costs more than that, for each module of a build where few have changed.
-- Returns the errors, and whether the module was up to date (so the context
-- was not reset).
buildOrSkipMod : {auto c : Ref Ctxt Defs} ->
                 {auto s : Ref Syn SyntaxInfo} ->
                 {auto o : Ref ROpts REPLOpts} ->
                 {auto h : Ref IfaceHashes (SortedMap ModuleIdent Int)} ->
                 {default True announce : Bool} -> -- print "Building" when building
                 FC -> Nat -> Nat -> BuildMod ->
                 Core (List Error, Bool)
buildOrSkipMod {announce} loc num len mod
   = do let sourceFile = buildFile mod
        let modNamespace = buildNS mod
        ttcFile <- getTTCFileName sourceFile "ttc"
        -- We'd expect any errors in nsToPath to have been caught by now
        -- since the imports have been built! But we still have to check.
        depFilesE <- traverse (nsToPath loc) (imports mod)
        let (ferrs, depFiles) = partitionEithers depFilesE

        log "import" 20 $ unwords $
          [ "Checking whether to rebuild "
          , sourceFile
          , "(" ++ ttcFile ++ ")"
          , "with dependencies:"
          ] ++ depFiles
        rebuild <- needsBuilding sourceFile ttcFile modNamespace depFiles

        if not rebuild
           then do -- what the context holds is not reported again (a
                   -- reset would forget it)
                   update Ctxt { warnings := [] }
                   put Syn initSyntax
                   ws <- emitWarningsAndErrors ferrs
                   pure (ws ++ ferrs, True)
           else do
             resetForModule
             u <- newRef UST initUState
             m <- newRef MD (initMetadata (PhysicalIdrSrc modNamespace))
             let (msgPrefix, buildMsg) = buildMessage num len mod
             log "import.file" 10 $ "Processing " ++ sourceFile
             errs <- process {announce} {u} {m} msgPrefix buildMsg sourceFile modNamespace
             forgetIfaceHash modNamespace
             ws <- emitWarningsAndErrors (if null errs then ferrs else errs)
             pure (ws ++ if null errs then ferrs else ferrs ++ errs, False)

export
buildMod : {auto c : Ref Ctxt Defs} ->
           {auto s : Ref Syn SyntaxInfo} ->
           {auto o : Ref ROpts REPLOpts} ->
           {default True announce : Bool} -> -- print "Building" when building
           FC -> Nat -> Nat -> BuildMod ->
           Core (List Error)
buildMod {announce} loc num len mod
   = do h <- initIfaceHashes
        (errs, skipped) <- buildOrSkipMod {announce} loc num len mod
        -- the context is reset after a module, whether it was built or not
        when skipped resetForModule
        pure errs

export
buildMods : {auto c : Ref Ctxt Defs} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto o : Ref ROpts REPLOpts} ->
            {auto h : Ref IfaceHashes (SortedMap ModuleIdent Int)} ->
            FC -> Nat -> Nat -> List BuildMod ->
            Core (List Error)
buildMods fc num len [] = pure []
buildMods fc num len (m :: ms)
    = do (errs, skipped) <- buildOrSkipMod fc num len m
         case (errs, ms) of
              ([], _ :: _) => buildMods fc (1 + num) len ms
              -- the context is reset after the last module, whether it was
              -- built or not (a module that is built resets it before)
              _ => do when skipped resetForModule
                      pure errs

||| Build the modules that the main file needs, and the main file. On
||| success the main file is then read again from its TTC file, with all its
||| imports, for the REPL (or whatever comes next), unless `reload` is False:
||| reading the whole of what the main file imports, transitively, costs as
||| much as checking a small module, and `--check` alone needs none of it.
export
buildDeps : {auto c : Ref Ctxt Defs} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto m : Ref MD Metadata} ->
            {auto u : Ref UST UState} ->
            {auto o : Ref ROpts REPLOpts} ->
            {default True reload : Bool} ->
            (mainFile : String) ->
            Core (List Error)
buildDeps {reload} fname
    = do mods <- getBuildMods EmptyFC [] fname
         log "import" 20 $ "Needs to rebuild: " ++ show mods
         h <- initIfaceHashes
         ok <- buildMods EmptyFC 1 (length mods) mods
         case ok of
              [] => if not reload then pure [] else
                    do -- On success, reload the main ttc in a clean context
                       clearCtxt; addPrimitives
                       modIdent <- ctxtPathToNS fname
                       put MD (initMetadata (PhysicalIdrSrc modIdent))
                       mainttc <- getTTCFileName fname "ttc"
                       log "import" 10 $ "Reloading " ++ show mainttc ++ " from " ++ fname
                       readAsMain mainttc

                       -- Load the associated metadata for interactive editing
                       mainttm <- getTTCFileName fname "ttm"
                       log "import" 10 $ "Reloading " ++ show mainttm
                       readFromTTM mainttm
                       pure []
              errs => pure errs -- Error happened, give up

-- The modules of all the files, which share their imports: the header of
-- each source file is read once (a package lists most of its modules, and
-- each of them imports many others).
getAllBuildMods : {auto c : Ref Ctxt Defs} ->
                  {auto o : Ref ROpts REPLOpts} ->
                  FC -> (done : List BuildMod) ->
                  (allFiles : List String) ->
                  Core (List BuildMod)
getAllBuildMods fc done allFiles
    = do a <- newRef AllMods []
         go a done allFiles
  where
    go : Ref AllMods (List (ModuleIdent, ModTree)) ->
         List BuildMod -> List String -> Core (List BuildMod)
    go a done [] = pure done
    go a done (f :: fs)
        = do ms <- getBuildModsWith a fc done f
             go a (ms ++ done) fs

-- There'll be duplicates, so if something is already built, drop it
dropLater : List BuildMod -> List BuildMod
dropLater = go empty
  where
    go : StringMap () -> List BuildMod -> List BuildMod
    go seen [] = []
    go seen (b :: bs)
        = case StringMap.lookup (buildFile b) seen of
               Just _ => go seen bs
               Nothing => b :: go (StringMap.insert (buildFile b) () seen) bs

export
buildAll : {auto c : Ref Ctxt Defs} ->
           {auto s : Ref Syn SyntaxInfo} ->
           {auto o : Ref ROpts REPLOpts} ->
           (allFiles : List String) ->
           Core (List Error)
buildAll allFiles
    = do mods <- getAllBuildMods EmptyFC [] allFiles
         let mods' = dropLater mods
         h <- initIfaceHashes
         buildMods EmptyFC 1 (length mods') mods'

||| Build one module of a package, whose imports are built already (in a
||| process started by buildAllParallel).
export
buildOneModule : {auto c : Ref Ctxt Defs} ->
                 {auto s : Ref Syn SyntaxInfo} ->
                 {auto o : Ref ROpts REPLOpts} ->
                 (file : String) ->
                 Core (List Error)
buildOneModule file
    = do ns <- ctxtPathToNS file
         modInfo <- readHeader file ns
         let mod = MkBuildMod file ns (map path (imports modInfo))
         buildMod {announce = False} EmptyFC 1 1 mod

%foreign "C:idris2i_1_spawnShell, libidris2i_1_support, idris_system.h"
prim__spawnShell : String -> PrimIO Int

%foreign "C:idris2i_1_waitAnyChild, libidris2i_1_support, idris_system.h"
prim__waitAnyChild : PrimIO Int

%foreign "C:idris2i_1_lastChildExitStatus, libidris2i_1_support, idris_system.h"
prim__lastChildExitStatus : PrimIO Int

-- (the `kill` of the C library, which System.Signal has but does not export,
-- with any signal: there is no `Signal` for SIGTERM)
%foreign "C:send_signal, libidris2i_1_support, idris_signal.h"
prim__sendSignal : (pid : Int) -> (signal : Int) -> PrimIO Int

-- SIGTERM, which is 15 on every POSIX system
sigTERM : Int
sigTERM = 15

record Job where
  constructor MkJob
  pid : Int
  mod : BuildMod
  logFile : String

||| Build the modules that `allFiles` need with up to `jobs` processes in
||| parallel: a module is built (by the command `childCmd file logFile`,
||| which writes its output to logFile) once its imports are built, and
||| modules that are up to date are skipped as by buildAll.  The output of
||| each process is printed when it ends, so that it is not interleaved.
export
buildAllParallel : {auto c : Ref Ctxt Defs} ->
                   {auto s : Ref Syn SyntaxInfo} ->
                   {auto o : Ref ROpts REPLOpts} ->
                   (jobs : Nat) ->
                   (childCmd : String -> String -> String) ->
                   (allFiles : List String) ->
                   Core (List Error)
buildAllParallel jobs childCmd allFiles
    = do mods <- dropLater <$> getAllBuildMods EmptyFC [] allFiles
         let inBuild = SortedSet.fromList (map buildNS mods)
         let len = length mods
         defs <- get Ctxt
         wd <- getWorkingDir
         let bdir = build_dir (dirs (options defs))
         let logDir = if isAbsolute bdir then bdir else wd </> bdir
         Right () <- coreLift $ mkdirAll logDir
           | Left err => throw (FileErr logDir err)
         -- When a process ends, the first module of the pending list that can
         -- be started is started, so put first the modules that the longest
         -- chain of other modules waits for: the build can not end before the
         -- longest chain does, however many processes there are.
         sizes <- traverse (\m => sourceSize m.buildFile) mods
         let chains = chainWeights (zip mods sizes)
         paths <- newRef TTCPaths SortedMap.empty
         -- The logs of the processes are named after this process: another
         -- build may run in the same directory at the same time.
         pid <- coreLift getPID
         let logPrefix = logDir </> "build-" ++ show pid ++ "-"
         jobsRef <- newRef RunningJobs []
         h <- initIfaceHashes
         -- If this process stops on an error, it stops its processes too, and
         -- waits for them: they would go on writing TTC files once it is gone.
         catch (loop inBuild len logPrefix
                     (sortBy (longestFirst chains) (zip [1 .. len] mods)) [] empty False)
               (\err => do stopJobs !(get RunningJobs)
                           throw err)
  where
    -- the longest chain first, then in the order of the list
    longestFirst : StringMap Nat -> (Nat, BuildMod) -> (Nat, BuildMod) -> Ordering
    longestFirst chains (i, a) (j, b)
        = compare (chainOf b) (chainOf a) <+> compare i j
      where
        chainOf : BuildMod -> Nat
        chainOf m = fromMaybe 0 (StringMap.lookup (show m.buildNS) chains)

    -- The size of a source file, which stands for the time to build it
    sourceSize : String -> Core Nat
    sourceSize file
        = do Right h <- coreLift $ openFile file Read
               | Left _ => pure 0 -- the process that builds it reports it
             Right size <- coreLift $ fileSize h
               | Left _ => do coreLift $ closeFile h
                              pure 0
             coreLift $ closeFile h
             pure (integerToNat (cast size))

    -- For each module, the weight of the longest chain of modules of this
    -- build that starts with it and goes through the modules that import it
    -- (the module itself included)
    chainWeights : List (BuildMod, Nat) -> StringMap Nat
    chainWeights ws
        = -- bound here, not in the `where` block: a local definition without
          -- arguments is computed again at each use
          let weights = StringMap.fromList (map (\(m, w) => (show m.buildNS, w)) ws)
              -- The modules, with the imports that are in the build; the
              -- modules that import the others come first, which is the
              -- order in which the chains are known, as the list has the
              -- imports before them
              entries = reverse $ map (\(m, _) => (show m.buildNS, importsInBuild weights m)) ws
          in passes entries (length ws) weights
      where
        importsInBuild : StringMap Nat -> BuildMod -> List (String, Nat)
        importsInBuild weights m
            = mapMaybe (\i => let k = show i in map (k,) (StringMap.lookup k weights))
                       m.imports

        -- what is below a module makes the chains of its imports longer
        relax : (StringMap Nat, Bool) -> (String, List (String, Nat)) -> (StringMap Nat, Bool)
        relax (cur, changed) (k, imported)
            = let below = fromMaybe 0 (StringMap.lookup k cur) in
                  foldl (\(acc, ch), (i, w) =>
                           if w + below > fromMaybe 0 (StringMap.lookup i acc)
                              then (StringMap.insert i (w + below) acc, True)
                              else (acc, ch))
                        (cur, changed) imported

        -- until nothing changes, which takes as many passes as there are
        -- modules at the most (two, when the imports come before the modules)
        passes : List (String, List (String, Nat)) -> Nat -> StringMap Nat -> StringMap Nat
        passes entries Z cur = cur
        passes entries (S k) cur
            = case foldl relax (cur, False) entries of
                   (next, True) => passes entries k next
                   (_, False) => cur

    -- An import of a module of this build that is not built yet
    blocked : SortedSet ModuleIdent -> SortedSet ModuleIdent -> BuildMod -> Bool
    blocked inBuild done mod
        = any (\i => contains i inBuild && not (contains i done)) (imports mod)

    -- The TTC file of an import, as nsToPath finds it. It is found once:
    -- most modules have the same imports, and the TTC files that are found
    -- stay where they are during the build (an import of this build is
    -- built before the modules that import it are looked at).
    ttcPath : {auto paths : Ref TTCPaths (SortedMap ModuleIdent String)} ->
              ModuleIdent -> Core (Either Error String)
    ttcPath ns
        = case SortedMap.lookup ns !(get TTCPaths) of
               Just path => pure (Right path)
               Nothing =>
                 do Right path <- nsToPath EmptyFC ns
                      | Left err => pure (Left err)
                    update TTCPaths (SortedMap.insert ns path)
                    pure (Right path)

    needed : {auto paths : Ref TTCPaths (SortedMap ModuleIdent String)} ->
             {auto h : Ref IfaceHashes (SortedMap ModuleIdent Int)} ->
             BuildMod -> Core Bool
    needed mod
        = do ttcFile <- getTTCFileName mod.buildFile "ttc"
             depFilesE <- traverse ttcPath mod.imports
             let (ferrs, depFiles) = partitionEithers depFilesE
             -- let the process report missing imports
             if not (null ferrs)
                then pure True
                else needsBuilding mod.buildFile ttcFile mod.buildNS depFiles

    -- Start what can be started, skip what is up to date.  Returns the
    -- pending, running and done modules, and whether anything changed.
    launch : {auto paths : Ref TTCPaths (SortedMap ModuleIdent String)} ->
             {auto h : Ref IfaceHashes (SortedMap ModuleIdent Int)} ->
             {auto jobsRef : Ref RunningJobs (List Job)} ->
             SortedSet ModuleIdent -> Nat -> String ->
             List (Nat, BuildMod) -> List Job -> SortedSet ModuleIdent ->
             Core (List (Nat, BuildMod), List Job, SortedSet ModuleIdent, Bool)
    launch inBuild len logPrefix [] running done = pure ([], running, done, False)
    launch inBuild len logPrefix ((num, mod) :: pending) running done
        = if blocked inBuild done mod || length running >= jobs
             then do (p, r, d, ch) <- launch inBuild len logPrefix pending running done
                     pure ((num, mod) :: p, r, d, ch)
             else if not !(needed mod)
             then do (p, r, d, _) <- launch inBuild len logPrefix pending running
                                            (SortedSet.insert mod.buildNS done)
                     pure (p, r, d, True)
             else do let logFile = logPrefix ++ show num ++ ".log"
                     pid <- coreLift $ primIO $ prim__spawnShell (childCmd mod.buildFile logFile)
                     when (pid < 0) $
                       throw (InternalError "Could not start a process to build \{mod.buildFile}")
                     let job = MkJob pid mod logFile
                     update RunningJobs (job ::)
                     let (msgPrefix, buildMsg) = buildMessage num len mod
                     iputStrLn (msgPrefix <++> "Building" <++> buildMsg)
                     (p, r, d, _) <- launch inBuild len logPrefix pending
                                            (job :: running) done
                     pure (p, r, d, True)

    -- Stop the processes that are still running (after an error), and wait
    -- for them, so that none is left writing files.  What they printed is
    -- dropped: the error is what is reported.
    stopJobs : List Job -> Core ()
    stopJobs [] = pure ()
    stopJobs js
        = do for_ js $ \j => coreLift_ (primIO $ prim__sendSignal j.pid sigTERM)
             waitAll js
      where
        waitAll : List Job -> Core ()
        waitAll [] = pure ()
        waitAll js
            = do pid <- coreLift $ primIO prim__waitAnyChild
                 let (done, others) = partition (\j => j.pid == pid) js
                 for_ done $ \j => coreLift_ (removeFile j.logFile)
                 -- (-1: there are no more children to wait for)
                 if pid < 0 then pure () else waitAll others

    -- Wait for a process to end, print what it printed.
    waitJob : {auto jobsRef : Ref RunningJobs (List Job)} ->
              List Job -> Core (Job, Bool, List Job)
    waitJob running
        = do pid <- coreLift $ primIO prim__waitAnyChild
             status <- coreLift $ primIO prim__lastChildExitStatus
             let (js, others) = partition (\j => j.pid == pid) running
             case js of
                  (j :: _) =>
                    do update RunningJobs (filter (\r => r.pid /= pid))
                       -- A process that did not get as far as starting the
                       -- compiler may have left no log: it printed nothing.
                       out <- either (const "") id <$> coreLift (readFile j.logFile)
                       unless (out == "") $ coreLift $ putStr out
                       ignore $ coreLift $ removeFile j.logFile
                       pure (j, status == 0, others)
                  [] => if pid < 0
                           then throw (InternalError "Lost track of the build processes")
                           else waitJob running -- not one of ours

    loop : {auto paths : Ref TTCPaths (SortedMap ModuleIdent String)} ->
           {auto h : Ref IfaceHashes (SortedMap ModuleIdent Int)} ->
           {auto jobsRef : Ref RunningJobs (List Job)} ->
           SortedSet ModuleIdent -> Nat -> String ->
           List (Nat, BuildMod) -> List Job -> SortedSet ModuleIdent -> Bool ->
           Core (List Error)
    loop inBuild len logPrefix pending running done failed
        = do (pending, running, done, changed) <-
                 the (Core (List (Nat, BuildMod), List Job, SortedSet ModuleIdent, Bool)) $
                   if failed then pure ([], running, done, False)
                             else launch inBuild len logPrefix pending running done
             if changed
                then loop inBuild len logPrefix pending running done failed
                else case running of
                  [] => if failed
                           then pure [GenericMsg EmptyFC "Building the package failed"]
                           else case pending of
                                  [] => pure []
                                  _ => throw (InternalError "Modules left that cannot be built")
                  _ => do (j, ok, running) <- waitJob running
                          -- (the process wrote the TTC file again)
                          forgetIfaceHash j.mod.buildNS
                          loop inBuild len logPrefix pending running
                               (if ok then SortedSet.insert j.mod.buildNS done else done)
                               (failed || not ok)
