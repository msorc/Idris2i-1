||| A stable, diffable text form of the public API of a module, for
||| `idris2i-1 --dump-api`.
|||
||| The text depends on the source only: it is sorted by name, it never
||| shows source positions, paths or the numbers in machine generated
||| names, and it is laid out without a page width (one declaration per
||| line), so that two builds of the same source give the same text and a
||| change to the API shows up as a line in a diff.
module Idris.Doc.API

import Core.Context
import Core.Env

import Idris.Pretty
import Idris.Resugar
import Idris.Syntax
import Idris.Syntax.Traversals

import TTImp.TTImp

import Data.List
import Data.SortedMap
import Data.Maybe
import Data.String

import Libraries.Data.ANameMap
import Libraries.Data.NameMap
import Libraries.Data.NatSet
import Libraries.Data.WithDefault
import Libraries.Text.PrettyPrint.Prettyprinter
import Libraries.Text.PrettyPrint.Prettyprinter.Render.String

%default covering

||| The printer options of the dump: implicit arguments shown, every name
||| fully qualified, and machine generated names shown without their number.
export
apiPPrint : PPrinter
apiPPrint = MkPPOpts
    { showImplicits = True
    , showMachineNames = False
    , showFullEnv = False
    , fullNamespace = True
    }

||| Every global definition whose source is in the given module, private
||| ones included. Shared by `--mkdoc` and `--dump-api`.
export
definedInModule : {auto c : Ref Ctxt Defs} ->
                  ModuleIdent -> Core (List GlobalDef)
definedInModule mod
    = do defs <- get Ctxt
         let ctxt = gamma defs
         map catMaybes $ for [1..nextEntry ctxt - 1] $ \ i =>
           do Just gdef <- lookupCtxtExact (Resolved i) ctxt
                | _ => pure Nothing
              let Just nfc = isNonEmptyFC $ location gdef
                | _ => do log "doc.module.definitions" 70 $ unwords
                            [ show mod ++ ":"
                            , show (fullname gdef)
                            , "has an empty FC"
                            ]
                          pure Nothing
              let PhysicalIdrSrc mod' = origin nfc
                | _ => pure Nothing
              let True = mod == mod'
                | _ => do log "doc.module.definitions" 60 $ unwords
                            [ show mod ++ ":"
                            , show (fullname gdef)
                            , "was defined in"
                            , show mod'
                            ]
                          pure Nothing
              pure (Just gdef)

render : Doc ann -> String
render d = Render.String.renderString (layoutUnbounded (the (Doc ()) (unAnnotate d)))

||| A name as it is written in a declaration: relative to the module's
||| namespace, an operator in brackets
showDeclName : Namespace -> Name -> String
showDeclName modNS (NS ns n)
    = let outer = reverse (unsafeUnfoldNamespace modNS)
          -- namespaces list their components innermost first
          full = reverse (unsafeUnfoldNamespace ns)
          rest = if outer `isPrefixOf` full then drop (length outer) full else full
      in concatMap (++ ".") rest ++ showDeclName modNS n
showDeclName _ (UN (Basic n))
    = if isOpName (UN (Basic n)) then "(" ++ n ++ ")" else n
showDeclName _ (UN (Field n)) = "." ++ n
showDeclName _ n = show n

showVis : Visibility -> String
showVis Private = "private"
showVis Export = "export"
showVis Public = "public export"

showTotReq : TotalReq -> String
showTotReq Total = "total"
showTotReq CoveringOnly = "covering"
showTotReq PartialOK = "partial"

||| Visibility, declared totality and deprecation, in that order
modifiers : GlobalDef -> List String
modifiers def
    = [showVis (collapseDefault $ visibility def)]
      ++ maybe [] (pure . showTotReq) (findSetTotal (flags def))
      ++ (if Context.Deprecate `elem` flags def then ["deprecated"] else [])

showRig : RigCount -> String
showRig = showCount

typeOf : {auto c : Ref Ctxt Defs} ->
         {auto s : Ref Syn SyntaxInfo} ->
         GlobalDef -> Core String
typeOf def
    = do defs <- get Ctxt
         ty <- normaliseHoles defs Env.empty (type def)
         ty <- toFullNames ty
         ptm <- resugar Env.empty ty
         -- `resugar` writes a name as its alias from an `import ... as`
         -- of the modules that happen to be loaded: write the full name
         ptm <- cleanPTerm (mapPTerm fullRef ptm)
         pure (render (prettyBy id ptm))
  where
    -- The generated name of an unnamed implementation says where the
    -- implementation is (`Num implementation at Prelude.Types:66:1--71:33`):
    -- write the name without it
    stableName : Name -> Name
    stableName (NS ns n) = NS ns (stableName n)
    stableName (DN s n)
        = if " implementation at " `isInfixOf` s then stableName n else DN s n
    stableName n = n

    -- The name of an argument that is a machine generated name has a number
    -- (`{a:2485} = a`) that depends on what was elaborated before: write it
    -- without
    argName : Name -> Name
    argName (MN s _) = UN (Basic ("{" ++ s ++ "}"))
    argName n = n

    fullKindedName : KindedName -> KindedName
    fullKindedName (MkKindedName nt full _)
        = let full' = stableName full in MkKindedName nt full' full'

    -- the operator of an infix, prefix or section is not a `PRef`
    fullOp : WithFC (OpStr' KindedName) -> WithFC (OpStr' KindedName)
    fullOp = map (map fullKindedName)

    fullRef : IPTerm -> IPTerm
    fullRef (PRef fc n) = PRef fc (fullKindedName n)
    -- (`mapPTerm` applies the function to the left operand of an infix
    -- operator but not to its subterms: do that here)
    fullRef (POp fc l op r) = POp fc (map (map (mapPTerm fullRef)) l) (fullOp op) r
    fullRef (PPrefixOp fc op x) = PPrefixOp fc (fullOp op) x
    fullRef (PSectionL fc op x) = PSectionL fc (fullOp op) x
    fullRef (PSectionR fc x op) = PSectionR fc x (fullOp op)
    fullRef (PNamedApp fc f n x) = PNamedApp fc f (argName n) x
    fullRef tm = tm

lookupDef : {auto c : Ref Ctxt Defs} -> Name -> Core (Maybe GlobalDef)
lookupDef n
    = do defs <- get Ctxt
         lookupCtxtExact n (gamma defs)

||| The name of the type at the head of the return type of a definition
returnHead : {auto c : Ref Ctxt Defs} -> GlobalDef -> Core (Maybe Name)
returnHead def
    = do defs <- get Ctxt
         ty <- toFullNames (type def)
         pure (go ty)
  where
    go : Term vs -> Maybe Name
    go (Bind _ _ (Pi {}) sc) = go sc
    go tm = case getFn tm of
                 Ref _ (TyCon {}) n => Just n
                 _ => Nothing

||| One entry of the dump of a module: a sort key and its lines
record Entry where
  constructor MkEntry
  ||| 0 for fixities, 1 for declarations, 2 for implementations
  group : Nat
  key : String
  lines : List String

||| The dump of one module
export
dumpModuleAPI : {auto c : Ref Ctxt Defs} ->
                {auto s : Ref Syn SyntaxInfo} ->
                ModuleIdent -> Core (List String)
dumpModuleAPI mod
    = do pp <- getPPrint
         setPPrint apiPPrint
         defs <- get Ctxt
         syn <- get Syn
         let modNS = miAsNamespace mod
         gdefs <- definedInModule mod
         gdefs <- traverse (\ d => pure ({ fullname := !(toFullNames (fullname d)) } d)) gdefs

         -- Names shown inside the entry of their interface or record
         let ifaceDefs = mapMaybe (isIface syn) gdefs
         let methodNames = concatMap (\ (_, i) => map (.name.val) (methods i)) ifaceDefs
         recordFields <- concat <$> traverse (fieldsOf defs) gdefs
         let inner = methodNames ++ map fst recordFields

         let shown = filter (\ d => visible d && not (fullname d `elem` inner))
                            gdefs
         entries <- traverse (entryFor syn modNS) shown

         let fixities = mapMaybe (fixityEntry modNS) (toList (fixities syn))
         let imports = sort $ map (render . prettyImport)
                     $ fromMaybe [] (SortedMap.lookup mod (modDocexports syn))

         setPPrint pp
         let sorted = sortBy (\ x, y => compare (x.group, x.key, x.lines)
                                                (y.group, y.key, y.lines))
                             (fixities ++ catMaybes entries)
         pure $ ("module " ++ show mod)
              :: map ("  " ++) (imports ++ concatMap lines sorted)
  where
    -- The generated name of an unnamed implementation (see
    -- `Idris.Elab.Implementation.mkImplName`); it says where the
    -- implementation is, so it is not printed
    unnamedImpl : Name -> Bool
    unnamedImpl (NS _ n) = unnamedImpl n
    unnamedImpl (DN _ (UN (Basic n))) = "__Impl_" `isPrefixOf` n
    unnamedImpl _ = False

    -- A name that belongs to the API: a name the user wrote, or the
    -- generated name of an unnamed implementation. Not the other machine
    -- generated names: case, with and where blocks, the functions of the
    -- methods of an implementation, the parent constraints of an interface.
    -- (nor the specialised copies of functions made by `%spec`, which
    -- are in the namespace `_PE` and the namespaces in it)
    userName : Name -> Bool
    userName (NS ns n)
        = if isPartialEvalNS ns then False else userName n
    userName (UN (Basic _)) = True
    userName (UN (Field _)) = True
    userName n = unnamedImpl n

    visible : GlobalDef -> Bool
    visible def = case definition def of
      DCon {} => False
      _ => collapseDefault (visibility def) /= Private
           && userName (fullname def)

    isIface : SyntaxInfo -> GlobalDef -> Maybe (GlobalDef, IFaceInfo)
    isIface syn def = (def,) <$> lookupExact (fullname def) (ifaces syn)

    -- The projections of a record defined in this module, with their name
    -- as a field
    fieldsOf : Defs -> GlobalDef -> Core (List (Name, Name))
    fieldsOf defs def = case (definition def, fullname def) of
      (TCon _ _ _ _ _ (Just [_]) _, NS ns (UN (Basic n))) =>
        do let recNS = ns <.> mkNamespace n
           let fields = getFieldNames (gamma defs) recNS
           fields <- traverse toFullNames fields
           pure $ concatMap
             (\ f => case f of
                  NS fns (UN (Field fn)) =>
                    [(f, f), (NS fns (UN (Basic fn)), f)]
                  _ => [(f, f)])
             fields
      _ => pure []

    fixityEntry : Namespace -> (Name, FixityInfo) -> Maybe Entry
    fixityEntry modNS (n, fx)
        = do nfc <- isNonEmptyFC fx.fc
             let PhysicalIdrSrc mod' = origin nfc
               | _ => Nothing
             guard (mod' == mod && fx.vis /= Private)
             let binding = case fx.bindingInfo of
                                NotBinding => []
                                Autobind => ["autobind"]
                                Typebind => ["typebind"]
             let name = showDeclName modNS (dropNS n)
             pure $ MkEntry 0 name
                 [unwords ([showVis fx.vis] ++ binding
                           ++ [show fx.fix, show fx.precedence, name])]

    conLine : Namespace -> Name -> Core (List String)
    conLine modNS cn
        = do Just cdef <- lookupDef cn
               | Nothing => pure []
             cn <- toFullNames cn
             pure ["  constructor " ++ showRig cdef.multiplicity
                     ++ showDeclName modNS cn ++ " : " ++ !(typeOf cdef)]

    entryFor : SyntaxInfo -> Namespace -> GlobalDef -> Core (Maybe Entry)
    entryFor syn modNS def
        = do let n = fullname def
             let mods = modifiers def
             ty <- typeOf def
             let decl = \ kw =>
                   unwords (mods ++ kw) ++ " " ++ showRig def.multiplicity
                     ++ showDeclName modNS n ++ " : " ++ ty
             let key = showDeclName modNS n
             case lookupExact n (ifaces syn) of
               Just iface => pure (Just (MkEntry 1 key !(ifaceLines decl def iface)))
               Nothing => case definition def of
                 TCon _ _ _ _ _ datacons _ =>
                   do let cons = fromMaybe [] datacons
                      let isRecord = case cons of
                                          [_] => True
                                          _ => False
                      defs <- get Ctxt
                      fields <- fieldsOf defs def
                      let kw = if isRecord && not (null fields)
                                  then "record" else "data"
                      -- the constructors of an `export` type are hidden
                      conLines <- if collapseDefault (visibility def) == Public
                                     then concat <$> traverse (conLine modNS) cons
                                     else pure []
                      fieldLines <- fieldLinesOf modNS fields
                      pure (Just (MkEntry 1 key (decl [kw] :: conLines ++ fieldLines)))
                 _ =>
                   do hd <- returnHead def
                      let ofIface = maybe False (\ h => isJust (lookupExact h (ifaces syn))) hd
                      -- The totality of the dictionary of an implementation
                      -- is not the one of its methods: it is not printed
                      let vis = showVis (collapseDefault $ visibility def)
                      if unnamedImpl n
                         then pure (Just (MkEntry 2 ty [vis ++ " implementation : " ++ ty]))
                         else if ofIface
                         then pure (Just (MkEntry 2 ty
                                [vis ++ " implementation [" ++ key ++ "] : " ++ ty]))
                         else pure (Just (MkEntry 1 key [decl []]))
      where

        fieldLinesOf : Namespace -> List (Name, Name) -> Core (List String)
        fieldLinesOf modNS fs
            = do -- one line per field: the `.x` projection
                 let projs = nub (map snd fs)
                 ls <- for projs $ \ p =>
                         do Just pdef <- lookupDef p
                              | Nothing => pure []
                            let fname = case dropNS p of
                                             UN (Field x) => x
                                             x => show x
                            pure ["  field " ++ showRig pdef.multiplicity
                                    ++ fname ++ " : " ++ !(typeOf pdef)]
                 pure (concat ls)

        ifaceLines : (List String -> String) -> GlobalDef -> IFaceInfo ->
                     Core (List String)
        ifaceLines decl def iface
            = do let ps = case params iface of
                               [] => []
                               ps => ["  parameters " ++ unwords (map show ps)]
                 -- the parameters that determine the implementation (`| a`)
                 let det = case definition def of
                             TCon _ _ detpos _ _ _ _ =>
                               if size detpos >= length (params iface) then []
                                  else ["  determining " ++ unwords
                                          (map show (NatSet.take detpos (params iface)))]
                             _ => []
                 cn <- toFullNames (iconstructor iface)
                 -- the type of the constructor has the parent constraints
                 -- and the methods, in order, with their quantities
                 icon <- do Just cdef <- lookupDef cn
                              | Nothing => pure []
                            let cname = case dropNS cn of
                                          UN _ => " " ++ showDeclName modNS cn
                                          _ => "" -- machine generated
                            pure ["  constructor" ++ cname ++ " : " ++ !(typeOf cdef)]
                 ms <- for (methods iface) $ \ m =>
                         do let mn = m.name.val
                            Just mdef <- lookupDef mn
                              | Nothing => pure []
                            mn <- toFullNames mn
                            pure ["  method " ++ showRig mdef.multiplicity
                                    ++ showDeclName modNS mn ++ " : " ++ !(typeOf mdef)]
                 pure (decl ["interface"] :: ps ++ det ++ icon ++ concat ms)
