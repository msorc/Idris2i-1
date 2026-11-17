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
import Data.String

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
                              modInfo <- readHeader file mod
                              let imps = map path (imports modInfo)
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

needsBuildingTime : {auto c : Ref Ctxt Defs} ->
                    (sourceFile : String) -> (ttcFile : String) ->
                    (depFiles : List String) -> Core Bool
needsBuildingTime sourceFile ttcFile depFiles
  = isTTCOutdated ttcFile (sourceFile :: depFiles)

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
                    (depFiles : List String) -> Core Bool
needsBuildingHash sourceFile ttcFile depFiles
  = do defs                <- get Ctxt
       sourceUnchanged <- unchangedHash defs.options.hashFn ttcFile sourceFile
       depFilesHashDiffers <- any id <$> traverse needsBuildingDepHash depFiles
       pure $ (not sourceUnchanged) || depFilesHashDiffers

export
needsBuilding :
  {auto c : Ref Ctxt Defs} ->
  {auto o : Ref ROpts REPLOpts} ->
  (sourceFile, ttcFile : String) -> List String -> Core Bool
needsBuilding sourceFile ttcFile depFiles
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
                  sourceFile ttcFile depFiles
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

export
buildMod : {auto c : Ref Ctxt Defs} ->
           {auto s : Ref Syn SyntaxInfo} ->
           {auto o : Ref ROpts REPLOpts} ->
           {default True announce : Bool} -> -- print "Building" when building
           FC -> Nat -> Nat -> BuildMod ->
           Core (List Error)
buildMod {announce} loc num len mod
   = do -- Also forget what the module built before set (%language,
        -- %pair, ...): the module is built as by a process of its own, which
        -- is how a parallel build (buildAllParallel) builds it.
        clearCtxt; update Ctxt { options $= clearNames }; addPrimitives
        lazyActive True; setUnboundImplicits True

        let sourceFile = buildFile mod
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
        rebuild <- needsBuilding sourceFile ttcFile depFiles

        u <- newRef UST initUState
        m <- newRef MD (initMetadata (PhysicalIdrSrc modNamespace))
        put Syn initSyntax

        errs <- ifThenElse (not rebuild) (pure []) $
           do let (msgPrefix, buildMsg) = buildMessage num len mod
              log "import.file" 10 $ "Processing " ++ sourceFile
              process {announce} {u} {m} msgPrefix buildMsg sourceFile modNamespace

        ws <- emitWarningsAndErrors (if null errs then ferrs else errs)
        pure (ws ++ if null errs then ferrs else ferrs ++ errs)

export
buildMods : {auto c : Ref Ctxt Defs} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto o : Ref ROpts REPLOpts} ->
            FC -> Nat -> Nat -> List BuildMod ->
            Core (List Error)
buildMods fc num len [] = pure []
buildMods fc num len (m :: ms)
    = case !(buildMod fc num len m) of
           [] => buildMods fc (1 + num) len ms
           errs => pure errs

export
buildDeps : {auto c : Ref Ctxt Defs} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto m : Ref MD Metadata} ->
            {auto u : Ref UST UState} ->
            {auto o : Ref ROpts REPLOpts} ->
            (mainFile : String) ->
            Core (List Error)
buildDeps fname
    = do mods <- getBuildMods EmptyFC [] fname
         log "import" 20 $ "Needs to rebuild: " ++ show mods
         ok <- buildMods EmptyFC 1 (length mods) mods
         case ok of
              [] => do -- On success, reload the main ttc in a clean context
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

%foreign "C:idris2_spawnShell, libidris2_support, idris_system.h"
prim__spawnShell : String -> PrimIO Int

%foreign "C:idris2_waitAnyChild, libidris2_support, idris_system.h"
prim__waitAnyChild : PrimIO Int

%foreign "C:idris2_lastChildExitStatus, libidris2_support, idris_system.h"
prim__lastChildExitStatus : PrimIO Int

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
         let inBuild = map buildNS mods
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
         loop inBuild len logDir
              (sortBy (longestFirst chains) (zip [1 .. len] mods)) [] [] False
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
    chainWeights ws = passes (length ws) weights
      where
        weights : StringMap Nat
        weights = StringMap.fromList (map (\(m, w) => (show m.buildNS, w)) ws)

        -- The modules, with the imports that are in the build; the modules
        -- that import the others come first, which is the order in which
        -- the chains are known, as the list has the imports before them
        entries : List (String, List (String, Nat))
        entries = reverse $ map (\(m, _) => (show m.buildNS, importsInBuild m)) ws
          where
            importsInBuild : BuildMod -> List (String, Nat)
            importsInBuild m = mapMaybe (\i => let k = show i in
                                                 map (k,) (StringMap.lookup k weights))
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
        passes : Nat -> StringMap Nat -> StringMap Nat
        passes Z cur = cur
        passes (S k) cur
            = case foldl relax (cur, False) entries of
                   (next, True) => passes k next
                   (_, False) => cur

    -- An import of a module of this build that is not built yet
    blocked : List ModuleIdent -> List ModuleIdent -> BuildMod -> Bool
    blocked inBuild done mod
        = any (\i => (i `elem` inBuild) && not (i `elem` done)) (imports mod)

    needed : BuildMod -> Core Bool
    needed mod
        = do ttcFile <- getTTCFileName mod.buildFile "ttc"
             depFilesE <- traverse (nsToPath EmptyFC) mod.imports
             let (ferrs, depFiles) = partitionEithers depFilesE
             -- let the process report missing imports
             if not (null ferrs)
                then pure True
                else needsBuilding mod.buildFile ttcFile depFiles

    -- Start what can be started, skip what is up to date.  Returns the
    -- pending, running and done modules, and whether anything changed.
    launch : List ModuleIdent -> Nat -> String ->
             List (Nat, BuildMod) -> List Job -> List ModuleIdent ->
             Core (List (Nat, BuildMod), List Job, List ModuleIdent, Bool)
    launch inBuild len logDir [] running done = pure ([], running, done, False)
    launch inBuild len logDir ((num, mod) :: pending) running done
        = if blocked inBuild done mod || length running >= jobs
             then do (p, r, d, ch) <- launch inBuild len logDir pending running done
                     pure ((num, mod) :: p, r, d, ch)
             else if not !(needed mod)
             then do (p, r, d, _) <- launch inBuild len logDir pending running
                                            (mod.buildNS :: done)
                     pure (p, r, d, True)
             else do let logFile = logDir </> "build-" ++ show num ++ ".log"
                     pid <- coreLift $ primIO $ prim__spawnShell (childCmd mod.buildFile logFile)
                     when (pid < 0) $
                       throw (InternalError "Could not start a process to build \{mod.buildFile}")
                     let (msgPrefix, buildMsg) = buildMessage num len mod
                     iputStrLn (msgPrefix <++> "Building" <++> buildMsg)
                     (p, r, d, _) <- launch inBuild len logDir pending
                                            (MkJob pid mod logFile :: running) done
                     pure (p, r, d, True)

    -- Wait for a process to end, print what it printed.
    waitJob : List Job -> Core (Job, Bool, List Job)
    waitJob running
        = do pid <- coreLift $ primIO prim__waitAnyChild
             status <- coreLift $ primIO prim__lastChildExitStatus
             let (js, others) = partition (\j => j.pid == pid) running
             case js of
                  (j :: _) =>
                    do Right out <- coreLift $ readFile j.logFile
                         | Left err => throw (FileErr j.logFile err)
                       unless (out == "") $ coreLift $ putStr out
                       ignore $ coreLift $ removeFile j.logFile
                       pure (j, status == 0, others)
                  [] => if pid < 0
                           then throw (InternalError "Lost track of the build processes")
                           else waitJob running -- not one of ours

    loop : List ModuleIdent -> Nat -> String ->
           List (Nat, BuildMod) -> List Job -> List ModuleIdent -> Bool ->
           Core (List Error)
    loop inBuild len logDir pending running done failed
        = do (pending, running, done, changed) <-
                 the (Core (List (Nat, BuildMod), List Job, List ModuleIdent, Bool)) $
                   if failed then pure ([], running, done, False)
                             else launch inBuild len logDir pending running done
             if changed
                then loop inBuild len logDir pending running done failed
                else case running of
                  [] => if failed
                           then pure [GenericMsg EmptyFC "Building the package failed"]
                           else case pending of
                                  [] => pure []
                                  _ => throw (InternalError "Modules left that cannot be built")
                  _ => do (j, ok, running) <- waitJob running
                          loop inBuild len logDir pending running
                               (if ok then j.mod.buildNS :: done else done)
                               (failed || not ok)
