module Idris.ProcessIdr

import Compiler.RefC.RefC
import Compiler.Scheme.Chez
import Compiler.Scheme.ChezSep
import Compiler.Scheme.Racket
import Compiler.Scheme.Gambit
import Compiler.ES.Node
import Compiler.ES.Javascript
import Compiler.Common
import Compiler.Inline
import Compiler.Interpreter.VMCode

import Core.Binary
import Core.Directory
import Core.Env
import Core.Hash
import Core.Metadata
import Core.Termination.Positivity
import Core.Unify
import Core.UniverseCheck

import Parser.Unlit

import TTImp.Elab.Check
import TTImp.ProcessDecls
import TTImp.ProcessDecls.Totality
import TTImp.TTImp

import Idris.Desugar
import Idris.Desugar.Mutual
import Idris.Parser
import Idris.REPL.Common
import Idris.Syntax
import Idris.Syntax.TTC
import Idris.Pretty
import Idris.Doc.String

import Data.Bits
import Data.Buffer
import Data.SortedMap
import Data.String

import System.File

%default covering

-- If we're on an incremental codegen, check to see if the ttc was
-- built with incremental.
export
missingIncremental : {auto c : Ref Ctxt Defs} ->
                   String -> Core Bool
missingIncremental ttcFile
  = catch (do s <- getSession
              if s.codegen `elem` s.incrementalCGs
                then do
                  incData <- readIncData ttcFile
                  pure $ isNothing $ lookup s.codegen incData
                else
                  pure False)
          (\error => pure False)

processDecls : {auto c : Ref Ctxt Defs} ->
               {auto u : Ref UST UState} ->
               {auto s : Ref Syn SyntaxInfo} ->
               {auto m : Ref MD Metadata} ->
               {auto o : Ref ROpts REPLOpts} ->
               List PDecl -> Core (List Error)

processDecl : {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              {auto s : Ref Syn SyntaxInfo} ->
              {auto m : Ref MD Metadata} ->
              {auto o : Ref ROpts REPLOpts} ->
              PDecl -> Core (List Error)

-- Special cases to avoid treating these big blocks as units
-- This should give us better error recovery (the whole block won't fail
-- as soon as one of the definitions fails)
processDecl (MkWithData _ $ PNamespace ns ps)
    = withExtendedNS ns $ processDecls ps
processDecl decl@(MkWithData _ $ PMutual ps)
    = let (tys, defs) = splitMutual ps in
      -- with --check-universes, the definitions of the block are one group
      -- (see Core.UniverseCheck)
      withUniverseGroup (UN (Basic ("mutual block at " ++ show decl.fc))) $
        processDecls (tys ++ defs)

processDecl decl
    = profileDecl (show decl.fc ++ concatMap ((" " ++) . show) (take 1 (definedIn [decl.val]))) $
      catch (do impdecls <- desugarDecl [] decl
                traverse_ (Check.processDecl [] (MkNested []) Env.empty) impdecls
                pure [])
            (\err => do giveUpConstraints -- or we'll keep trying...
                        pure [err])

processDecls decls
    = do errs <- concat <$> traverse processDecl decls
         Nothing <- checkDelayedHoles
             | Just err => pure (if null errs then [err] else errs)
         pure errs

readModule : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             {auto s : Ref Syn SyntaxInfo} ->
             (full : Bool) -> -- load everything transitively (needed for REPL and compiling)
             FC ->
             (visible : Bool) -> -- Is import visible to top level module?
             (imp : ModuleIdent) -> -- Module name to import
             (as : Namespace) -> -- Namespace to import into
             Core ()
readModule full loc vis imp as
    = do defs <- get Ctxt
         let False = (imp, vis, as) `elem` map snd (allImported defs)
             | True => when vis (setVisible (miAsNamespace imp))
         Right fname <- nsToPath loc imp
               | Left err => throw err
         Just (syn, hash, more) <- readFromTTC False {extra = SyntaxInfo}
                                                  {cacheAs = Just "SyntaxInfo"}
                                                  loc vis fname imp as
              | Nothing => when vis (setVisible (miAsNamespace imp)) -- already loaded, just set visibility
         extendSyn syn

         defs <- get Ctxt
         modNS <- getNS
         when vis $ setVisible (miAsNamespace imp)
         traverse_ (\ mimp =>
                       do let m = fst mimp
                          let reexp = fst (snd mimp)
                          let as = snd (snd mimp)
                          when (reexp || full) $ readModule full loc reexp m as) more
         setNS modNS

readImport : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             {auto s : Ref Syn SyntaxInfo} ->
             Bool -> Import -> Core ()
readImport full imp
    = do readModule full (loc imp) True (path imp) (nameAs imp)
         addImported (path imp, reexport imp, nameAs imp)

||| Adds new import to the namespace without changing the current top-level namespace
export
addImport : {auto c : Ref Ctxt Defs} ->
            {auto u : Ref UST UState} ->
            {auto s : Ref Syn SyntaxInfo} ->
            Import -> Core ()
addImport imp
    = do topNS <- getNS
         readImport True imp
         setNS topNS

readImportMeta : {auto c : Ref Ctxt Defs} ->
                 Import -> Core (Bool, (Namespace, Int))
readImportMeta imp
    = do Right ttcFileName <- nsToPath (loc imp) (path imp)
               | Left err => throw err
         (_, interfaceHash) <- readHashes ttcFileName
         pure (reexport imp, (nameAs imp, interfaceHash))

prelude : Import
prelude = MkImport (MkFC (Virtual Interactive) (0, 0) (0, 0)) False
                     (nsAsModuleIdent preludeNS) preludeNS

export
readPrelude : {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              {auto s : Ref Syn SyntaxInfo} ->
              Bool -> Core ()
readPrelude full
    = do readImport full prelude
         setNS mainNS

-- Import a TTC for use as the main file (e.g. at the REPL)
export
readAsMain : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             {auto s : Ref Syn SyntaxInfo} ->
             (fname : String) -> Core ()
readAsMain fname
    = do Just (syn, _, more) <- readFromTTC {extra = SyntaxInfo}
                                             {cacheAs = Just "SyntaxInfo"}
                                             True EmptyFC True fname (nsAsModuleIdent emptyNS) emptyNS
              | Nothing => throw (InternalError "Already loaded")

         replNS <- getNS
         replNestedNS <- getNestedNS
         extendSyn syn

         -- Read the main file's top level imported modules, so we have access
         -- to their names (and any of their public imports)
         ustm <- get UST
         traverse_ (\ mimp =>
                       do let m = fst mimp
                          let as = snd (snd mimp)
                          readModule True emptyFC True m as
                          addImported (m, True, as)) more

         -- also load the prelude, if required, so that we have access to it
         -- at the REPL.
         when (not (noprelude !getSession)) $
              readModule True emptyFC True (nsAsModuleIdent preludeNS) preludeNS

         -- We're in the namespace from the first TTC, so use the next name
         -- from that for the fresh metavariable name generation
         -- TODO: Maybe we should record this per namespace, since this is
         -- a little bit of a hack? Or maybe that will have too much overhead.
         update UST { nextName := nextName ustm }

         setModuleNS replNS
         setNestedNS replNestedNS

addPrelude : List Import -> List Import
addPrelude imps
  = if not (nsAsModuleIdent preludeNS `elem` map path imps)
       then prelude :: imps
       else imps

export
readHeader : {auto c : Ref Ctxt Defs} ->
             {auto o : Ref ROpts REPLOpts} ->
             (path : String) -> (origin : ModuleIdent) -> Core Module
readHeader path origin
    = do Right res <- coreLift (readFile path)
            | Left err => throw (FileErr path err)
         -- Stop at the first :, that's definitely not part of the header, to
         -- save lexing the whole file unnecessarily
         setCurrentElabSource res -- for error printing purposes
         let Right (ws, decor, mod)
            = runParserTo (PhysicalIdrSrc origin)
                          (isLitFile path) (is ':') res
                          (progHdr (PhysicalIdrSrc origin))
            | Left err => throw err
         traverse_ recordWarning ws
         pure mod

-- A step of the FNV-1a hash, on 64 bits at a time (inlined: the Int64 values
-- of the loops below are not boxed)
%inline
fnvStep : Int64 -> Int64 -> Int64
fnvStep h x = prim__xor_Int64 h x * 1099511628211

-- The hash of the bytes of a buffer, eight at a time, then those that are
-- left
hashBuffer : Buffer -> (len : Int) -> IO Int64
hashBuffer b len = ones (8 * (len `div` 8)) !(eights 0 (-3750763034362895579))
  where
    eights : Int -> Int64 -> IO Int64
    eights i h
        = if i + 8 > len
             then pure h
             else eights (i + 8) (fnvStep h !(getInt64 b i))

    ones : Int -> Int64 -> IO Int64
    ones i h
        = if i >= len
             then pure (fnvStep h (cast len))
             else ones (i + 1) (fnvStep h (cast !(getBits8 b i)))

||| The key of a source file, which the TTC file of its module records with
||| the imports of its header (see `Defs.sourceHeader`): a hash (FNV-1a, 64
||| bits) of its content, and the content. Nothing for a literate file,
||| whose header is not recorded, or when it cannot be read.
export
sourceKey : (path : String) -> Core (Maybe (Bits64, Binary))
sourceKey path
    = if isJust (isLitFile path)
         then pure Nothing
         else do Right bin <- coreLift $ readFromFile path
                   | Left _ => pure Nothing
                 h <- coreLift $ hashBuffer (buf bin) (cast (used bin))
                 pure (Just (cast h, bin))

||| The modules that a source file imports, as its header says. They are read
||| from the TTC file of the module when it was written by this compiler from
||| the same content of the source file (see `sourceKey`), which saves lexing
||| and parsing the header: finding out which modules a package needs to build
||| reads the header of each of them.
export
readHeaderImports : {auto c : Ref Ctxt Defs} ->
                    {auto o : Ref ROpts REPLOpts} ->
                    (file : String) -> (origin : ModuleIdent) ->
                    Core (List ModuleIdent)
readHeaderImports file origin
    = do Just (key, bin) <- sourceKey file
           | Nothing => fromSource
         -- (no TTC file for a source file outside the source directory)
         Just ttcFile <- catch (Just <$> getTTCFileName file "ttc")
                               (\_ => pure Nothing)
           | Nothing => fromSource
         Just (key', imps) <- readSourceHeader ttcFile
           | Nothing => fromSource
         if key /= key'
            then fromSource
            else do -- as readHeader does
                    res <- coreLift $ getString (buf bin) 0 (cast (used bin))
                    setCurrentElabSource res
                    pure imps
  where
    fromSource : Core (List ModuleIdent)
    fromSource = map path . imports <$> readHeader file origin

%foreign "scheme:collect"
         "RefC:idris2_refc_gc"
prim__gc : Int -> PrimIO ()

gc : IO ()
gc = primIO $ prim__gc 4

export
addPublicHash : {auto c : Ref Ctxt Defs} ->
                (Bool, (Namespace, Int)) -> Core ()
addPublicHash (True, (mod, h)) = do addHash mod
                                    addHash h
                                    log "module.hash" 15 "Adding hash for a public import of \{show mod}"
addPublicHash _ = pure ()

||| Determine if the TTC is outdated based on any of the given
||| source or dependency source file names.
export
isTTCOutdated : {auto c : Ref Ctxt Defs} ->
                (ttcFile : String) ->
                (sourceFiles : List String) ->
                Core Bool
isTTCOutdated ttcFile sourceFiles
  = do ttcTime  <- modTime ttcFile
       srcTimes <- traverse modTime sourceFiles
       log "module.hash" 20 $
         unlines $
           "Checking whether source code mod times are newer than \{show ttcTime}; src times:"
           :: zipWith (\ src, tm => "\{src} : \{show tm}") sourceFiles srcTimes
       pure $ any (>= ttcTime) srcTimes

||| If the source files hash hasn't changed
export
unchangedHash : (hashFn : Maybe String) -> (ttcFileName : String) -> (sourceFileName : String) -> Core Bool
unchangedHash hashFn ttcFileName sourceFileName
  = do Just sourceCodeHash        <- hashFileWith hashFn sourceFileName
             | _ => pure False
       (Just storedSourceHash, _) <- readHashes ttcFileName
             | _ => pure False
       pure $ sourceCodeHash == storedSourceHash

||| Whether the module of a TTC file is up to date, so that it is not built
||| again: its source file is unchanged (as the caller found out), the file
||| was written by this compiler, the interface hashes of its imports, with
||| the namespaces they are imported as, are those that the file records,
||| and the file has the data of the incremental code generators in use.
||| `processMod` skips a module by this, and the build driver
||| (`Idris.ModTree.needsBuilding`) does not even start building a module
||| whose imports were written again with the same interface.
export
unchangedModule : {auto c : Ref Ctxt Defs} ->
                  (ttcFile : String) -> (sourceUnchanged : Bool) ->
                  (importHashes : List (Namespace, Int)) -> Core Bool
unchangedModule ttcFile False importHashes = pure False
unchangedModule ttcFile True importHashes
    = do True <- builtByThisCompiler ttcFile
           | False => pure False
         stored <- readImportHashes ttcFile
         log "module.hash" 5 $ "Stored interface hashes of " ++ ttcFile ++ ":\n" ++
           show (sort stored)
         if sort importHashes /= sort stored
            then pure False
            else not <$> missingIncremental ttcFile

export
getCG : {auto o : Ref ROpts REPLOpts} ->
        CG -> Core (Maybe Codegen)
getCG Chez = pure $ Just codegenChez
getCG ChezSep = pure $ Just codegenChezSep
getCG Racket = pure $ Just codegenRacket
getCG Gambit = pure $ Just codegenGambit
getCG Node = pure $ Just codegenNode
getCG Javascript = pure $ Just codegenJavascript
getCG RefC = pure $ Just codegenRefC
getCG VMCodeInterp = pure $ Just codegenVMCodeInterp
getCG (Other s) = getCodegen s

export
findCG : {auto o : Ref ROpts REPLOpts} ->
         {auto c : Ref Ctxt Defs} -> Core (Maybe Codegen)
findCG
    = do defs <- get Ctxt
         getCG (codegen (session (options defs)))

||| Process everything in the module; return the syntax information which
||| needs to be written to the TTC (e.g. exported infix operators)
||| Returns 'Nothing' if it didn't reload anything
processMod : {auto c : Ref Ctxt Defs} ->
             {default True announce : Bool} -> -- print msg when building
             {auto u : Ref UST UState} ->
             {auto s : Ref Syn SyntaxInfo} ->
             {auto m : Ref MD Metadata} ->
             {auto o : Ref ROpts REPLOpts} ->
             (sourceFileName : String) ->
             (ttcFileName : String) ->
             (msg : Doc IdrisAnn) ->
             (sourcecode : String) ->
             (origin : ModuleIdent) ->
             Core (Maybe (List Error))
processMod {announce} sourceFileName ttcFileName msg sourcecode origin
    = catch (do
        setCurrentElabSource sourcecode
        session <- getSession

        -- Just read the header to start with (this is to get the imports and
        -- see if we can avoid rebuilding if none have changed)
        moduleHeader <- readHeader sourceFileName origin
        let ns = moduleNS moduleHeader
        -- saved in the TTC file, for readHeaderImports
        key <- map fst <$> sourceKey sourceFileName
        update Ctxt { sourceHeader := map (, map path (imports moduleHeader)) key }

        -- Add an implicit prelude import
        let allImports =
          if (session.noprelude || moduleNS moduleHeader == nsAsModuleIdent preludeNS)
             then imports moduleHeader
             else addPrelude $ imports moduleHeader

        importMetas <- traverse readImportMeta allImports
        let importInterfaceHashes = snd <$> importMetas

        defs <- get Ctxt
        log "module.hash" 5 $ "Interface hash of " ++ show ns ++ ": " ++ show (ifaceHash defs)
        log "module.hash" 5 $ "Import Interface hashes of " ++ show ns ++ " hashes:\n" ++
          show (sort importInterfaceHashes)

        let isUnchanged = if session.checkHashesInsteadOfModTime
                             then unchangedHash (defs.options.hashFn)
                             else (\ttc,src => not <$> (isTTCOutdated ttc [src]))
        sourceUnchanged <- isUnchanged ttcFileName sourceFileName

        -- If neither the source nor the interface hashes of imports have changed then no rebuilding is needed
        if !(unchangedModule ttcFileName sourceUnchanged importInterfaceHashes)
           then -- Hashes the same, source up to date, just set the ns
                -- for the REPL
                do setModuleNS (miAsNamespace ns)
                   pure Nothing
           else -- needs rebuilding
             do when announce $ iputStrLn msg
                Right (ws, MkState decor hnames, mod) <-
                    logTime 2 ("Parsing " ++ sourceFileName) $ profile "parse" $
                      pure $ runParser (PhysicalIdrSrc origin)
                                       (isLitFile sourceFileName)
                                       sourcecode
                                       (do p <- prog (PhysicalIdrSrc origin); eoi; pure p)
                  | Left err => pure (Just [err])
                traverse_ recordWarning ws

                -- save the doc info for the current module
                log "doc.module" 10 $ unlines
                  [ "Recording doc", documentation moduleHeader
                  , "and imports " ++ show (imports moduleHeader)
                  , "for module " ++ show (moduleNS moduleHeader)
                  ]
                addModDocInfo
                  (moduleNS moduleHeader)
                  (documentation moduleHeader)
                  (filter reexport $ imports moduleHeader)

                addSemanticDecorations decor
                update Syn { holeNames := hnames }

                initHash
                traverse_ addPublicHash (sort importMetas)
                resetNextVar
                when (ns /= nsAsModuleIdent mainNS) $
                      when (ns /= origin) $
                          throw (GenericMsg mod.headerLoc
                                   ("Module name " ++ show ns ++
                                    " does not match file name " ++ show sourceFileName))

                -- read import ttcs in full here
                -- Note: We should only import .ttc - assumption is that there's
                -- a phase before this which builds the dependency graph
                -- (also that we only build child dependencies if rebuilding
                -- changes the interface - will need to store a hash in .ttc!)
                logTime 2 "Reading imports" $ profile "import" $
                   traverse_ (readImport False) allImports

                -- Before we process the source, make sure the "hide_everywhere"
                -- names are set to private (TODO, maybe if we want this?)
--                 defs <- get Ctxt
--                 traverse (\x => setVisibility emptyFC x Private) (hiddenNames defs)
                setModuleNS (miAsNamespace ns)
                errs <- logTime 2 "Processing decls" $
                            processDecls (decls mod)
                totErrs <- logTime 3 ("Totality check overall")
                            getTotalityErrors
                uErrs <- if isNil errs
                            then catch (do finishModuleUniverses mod.headerLoc
                                           pure [])
                                       (\err => pure [err])
                            else pure []
                let errs = errs ++ totErrs ++ uErrs
--                 coreLift $ gc

                when (isNil errs) $
                   logTime 3 "Record positive parameters" $ recordPositiveParams
                when (isNil errs) $
                   logTime 2 "Compile defs" $ profile "compile" compileAndInlineAll

                -- Save the import hashes for the imports we just read.
                -- If they haven't changed next time, and the source
                -- file hasn't changed, no need to rebuild.
                update Ctxt { importHashes := importInterfaceHashes }
                pure (Just errs))
          (\err => pure (Just [err]))

-- Process a file. Returns any errors, rather than throwing them, because there
-- might be lots of errors collected across a whole file.
export
process : {auto c : Ref Ctxt Defs} ->
          {default True announce : Bool} -> -- print the build message
          {auto m : Ref MD Metadata} ->
          {auto u : Ref UST UState} ->
          {auto s : Ref Syn SyntaxInfo} ->
          {auto o : Ref ROpts REPLOpts} ->
          (msgPrefix : Doc IdrisAnn) ->
          (buildMsg : Doc IdrisAnn) ->
          FileName ->
          (moduleIdent : ModuleIdent) ->
          Core (List Error)
process {announce} msgPrefix buildMsg sourceFileName ident
    = profileModule sourceFileName $
      do Right res <- coreLift (readFile sourceFileName)
               | Left err => pure [FileErr sourceFileName err]
         catch (do ttcFileName <- getTTCFileName sourceFileName "ttc"
                   Just errs <- logTime 1 ("Elaborating " ++ sourceFileName) $
                                   processMod {announce} sourceFileName ttcFileName
                                              (msgPrefix <++> "Building" <++> buildMsg)
                                              res ident
                     | Nothing => do log "module" 10 $ show $ msgPrefix <++> "Skipping" <++> buildMsg
                                     pure [] -- skipped it
                   if isNil errs
                      then
                        do ns <- ctxtPathToNS sourceFileName
                           makeBuildDirectory ns
                           traverse_
                              (\cg =>
                                  do Just cgdata <- getCG cg
                                          | Nothing =>
                                              coreLift $ putStrLn $ "No incremental code generator for " ++ show cg
                                     Just res <- incCompile cgdata sourceFileName
                                          | Nothing => pure ()
                                     setIncData cg res)
                              (incrementalCGs !getSession)

                           profile "ttc.write" $ writeToTTC !(get Syn) sourceFileName ttcFileName
                           ttmFileName <- getTTCFileName sourceFileName "ttm"
                           profile "ttc.write" $ writeToTTM ttmFileName
                           pure []
                      else do pure errs)
               (\err => pure [err])
