||| The field representation table of the data constructors: what the
||| declared type of each argument of a constructor says about the values that
||| it holds at run time (see `Core.CompileExpr.FieldRep` and
||| docs/source/backends/refc-flat-layout.rst).
|||
||| The table is computed once, when the data type is declared (see
||| `setConFields`, called by TTImp.ProcessData), and saved in the
||| constructor's flags.  The compiled definition of the constructor
||| (`MkCon`) gets it from there, without its erased arguments.  It is not
||| computed again in another module, where the types that a field mentions
||| may reduce differently (a definition that is not `public export` does not
||| reduce there): every module must compile a constructor with the same
||| table.
module Core.FieldRep

import Core.Case.CaseTree
import Core.CompileExpr
import Core.Context
import Core.Context.Log
import Core.Env
import Core.Normalise
import Core.Value

import Libraries.Data.NatSet
import Libraries.Data.WithDefault

%default covering

||| The values of a primitive type that a field may hold unboxed: the fixed
||| width ones.
primRep : PrimType -> FieldRep
primRep IntegerType = FBoxed
primRep StringType = FBoxed
primRep WorldType = FBoxed
primRep t = FPrim t

||| The flags of the constructor `n`, or none if it is not known.
conFlags : Defs -> Name -> Core (List DefFlag)
conFlags defs n
    = do Just gdef <- lookupCtxtExact n (gamma defs)
              | Nothing => pure []
         pure (flags gdef)

||| The table in the flags of a constructor, if it has one.
conFieldsFlag : List DefFlag -> Maybe (List FieldRep)
conFieldsFlag [] = Nothing
conFieldsFlag (ConFields fs :: _) = Just fs
conFieldsFlag (_ :: fs) = conFieldsFlag fs

||| The run time values of a type, when the rule recognises it: a fixed width
||| primitive type; an enumeration (all its constructors are flagged `ENUM`,
||| so the enumeration optimisation compiles them to the constant of
||| `enumPrimType`); a newtype (its only constructor is compiled away) whose
||| field holds such values by its own table.  Anything else is boxed: a type
||| variable or another stuck term, a function, `Lazy`, `Type`, other data
||| types.
typeRep : Defs -> ClosedNF -> Core FieldRep
typeRep defs (NPrimVal _ (PrT t)) = pure (primRep t)
typeRep defs (NTCon _ tn _ _)
    = do Just (TCon _ _ _ _ _ (Just cons@(_ :: _)) _) <- lookupDefExact tn (gamma defs)
              | _ => pure FBoxed
         Just k <- enumSize cons
              | Nothing => newtypeRep cons
         pure (FPrim (enumPrimType k))
  where
    enumOf : List DefFlag -> Maybe Nat
    enumOf [] = Nothing
    enumOf (ConType (ENUM k) :: _) = Just k
    enumOf (_ :: fs) = enumOf fs

    -- The number of constructors of the enumeration, if all of `cs` are
    -- flagged as constructors of one.
    enumSize : List Name -> Core (Maybe Nat)
    enumSize [] = pure Nothing
    enumSize [c] = pure (enumOf !(conFlags defs c))
    enumSize (c :: cs)
        = do Just k <- pure (enumOf !(conFlags defs c))
                  | Nothing => pure Nothing
             Just k' <- enumSize cs
                  | Nothing => pure Nothing
             pure (if k == k' then Just k else Nothing)

    -- Only the newtypes whose field is unboxed by their own table: the field
    -- of `Identity a` is boxed, even in `Identity Double`, since the table
    -- does not depend on the arguments of the type.
    newtypeRep : List Name -> Core FieldRep
    newtypeRep [c]
        = do Just (DCon _ _ (Just (_, pos))) <- lookupDefExact c (gamma defs)
                  | _ => pure FBoxed
             let Just fs = conFieldsFlag !(conFlags defs c)
                  | Nothing => pure FBoxed
             case drop pos fs of
                  (r@(FPrim _) :: _) => pure r
                  _ => pure FBoxed
    newtypeRep _ = pure FBoxed
typeRep defs _ = pure FBoxed

||| The representations of the first `arity` arguments of the constructor
||| type `ty`.  An erased argument is boxed (it is not a field at run time).
||| The arguments that come before a field are stuck variables in its type,
||| so a field whose type depends on them is boxed unless it reduces anyway.
export
conFieldReps : {auto c : Ref Ctxt Defs} ->
               (arity : Nat) -> ClosedTerm -> Core (List FieldRep)
conFieldReps arity ty
    = do defs <- get Ctxt
         go defs arity 0 !(nf defs Env.empty ty)
  where
    go : Defs -> Nat -> Int -> ClosedNF -> Core (List FieldRep)
    go defs Z _ _ = pure []
    go defs (S k) i (NBind fc x (Pi _ rig _ aty) scf)
        = do rep <- if isErased rig
                       then pure FBoxed
                       else typeRep defs !(evalClosure defs aty)
             sc <- scf defs (toClosure defaultOpts Env.empty
                               (Ref fc Bound (MN "field" i)))
             (rep ::) <$> go defs k (i + 1) sc
    -- (The type has fewer binders than the arity says: this does not happen
    -- for a constructor, but if it did, the other arguments would be boxed.)
    go defs (S k) i _ = pure (replicate (S k) FBoxed)

||| Compute the table of the data constructor `n` and save it in its flags.
export
setConFields : {auto c : Ref Ctxt Defs} -> FC -> Name -> Core ()
setConFields fc n
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact n (gamma defs)
              | Nothing => pure ()
         let DCon _ arity _ = definition gdef
              | _ => pure ()
         fs <- conFieldReps arity (type gdef)
         setFlag fc n (ConFields fs)

||| Is it a constructor that Compiler.Opts.Constructor makes intrinsic?
intrinsic : List DefFlag -> Bool
intrinsic = any isIntrinsic
  where
    isIntrinsic : DefFlag -> Bool
    isIntrinsic (ConType NIL) = True
    isIntrinsic (ConType CONS) = True
    isIntrinsic (ConType NOTHING) = True
    isIntrinsic (ConType JUST) = True
    isIntrinsic _ = False

||| Flag the constructors `cons` of the type `tn` `NoIntrinsic` if they are
||| list or option shaped (made intrinsic otherwise) and one of
||| them has a field that a back end may store raw (`rawField`): then none of
||| them is compiled to an intrinsic constructor (see
||| Compiler.Opts.Constructor), whose fields are boxed, and which stands for
||| the constructors of every type of the same shape.  All of them, so that
||| a type's constructors are either all intrinsic or none.
export
setNoIntrinsic : {auto c : Ref Ctxt Defs} -> FC -> Name -> List Name -> Core ()
setNoIntrinsic fc tn cons
    = do defs <- get Ctxt
         fs <- traverse (conFlags defs) cons
         when (any intrinsic fs && any (maybe False (any rawField) . conFieldsFlag) fs) $
           do log "declare.data.nointrinsic" 1 $ "Constructors of " ++ show !(toFullNames tn) ++ " keep their names"
              traverse_ (\ n => setFlag fc n NoIntrinsic) cons

||| The table of the constructor `n`, with `arity` arguments, without its
||| erased arguments `erased` (as the arguments of a constructor application
||| are in CExp).  A constructor without a table (there is none for type
||| constructors) has every field boxed.
export
compiledConFields : {auto c : Ref Ctxt Defs} ->
                    Name -> (arity : Nat) -> (erased : NatSet) -> Core (List FieldRep)
compiledConFields n arity erased
    = do defs <- get Ctxt
         fs <- conFlags defs n
         pure $ case conFieldsFlag fs of
                     Just reps =>
                       if length reps == arity
                          then NatSet.drop erased reps
                          else replicate (arity `minus` size erased) FBoxed
                     Nothing => replicate (arity `minus` size erased) FBoxed

||| The table of the compiled definition of the constructor `n` (its
||| `MkCon`), if the context has one: for a code generator that needs the
||| table of a constructor whose definition is not among those it compiles (as
||| with incremental compilation).
export
compiledFieldsOf : {auto c : Ref Ctxt Defs} -> Name -> Core (Maybe (List FieldRep))
compiledFieldsOf n
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact n (gamma defs)
              | Nothing => pure Nothing
         pure $ case compexpr gdef of
                     Just (MkCon _ _ _ fs) => Just fs
                     _ => Nothing

||| The full names of the layout of arrays (Data.IOArray.Flat in base).
flatNames : (Name, Name, Name)
flatNames = let ns = mkNamespace "Data.IOArray.Flat" in
                (NS ns (UN $ Basic "Flat"), NS ns (UN $ Basic "MkFlat"),
                 NS ns (UN $ Basic "MkLayout"))

||| For a record of one constructor, without parameters, whose fields are all
||| stored raw (`rawField`), the implementation of `Flat` that lays the
||| elements of its arrays out inline: the code of its layout (see
||| Data.IOArray.Flat.Layout), a hint for the searches of a `Flat` of the
||| record.  Only when Data.IOArray.Flat is loaded (by the public imports of
||| the module: the hint refers to it), as the module that declares the
||| record does not otherwise see it.  The implementation is made here, from
||| the table, so that the layout cannot disagree with the cells (see the
||| RefC back end); it cannot be written by hand (the constructor of
||| `Layout` is private).
export
addFlatHint : {auto c : Ref Ctxt Defs} -> FC -> Name -> List Name -> Core ()
addFlatHint fc tn [con]
    = do defs <- get Ctxt
         let (flat, mkFlat, mkLayout) = flatNames
         Just fdef <- lookupCtxtExact flat (gamma defs)
              | Nothing => pure ()
         Just (TCon tyArity _ _ _ _ _ _) <- lookupDefExact tn (gamma defs)
              | _ => pure ()
         Just cdef <- lookupCtxtExact con (gamma defs)
              | Nothing => pure ()
         let DCon tag arity Nothing = definition cdef
              | _ => pure ()
         let Just fs = conFieldsFlag (flags cdef)
              | Nothing => pure ()
         let fields = NatSet.drop (eraseArgs cdef) fs
         if tyArity /= 0 || null fields || not (all rawField fields)
            || tag < 0 || tag >= 65536 || length fields >= 65536
            then pure () else do
              Just (DCon ftag far _) <- lookupDefExact mkFlat (gamma defs)
                   | _ => pure ()
              Just (DCon ltag lar _) <- lookupDefExact mkLayout (gamma defs)
                   | _ => pure ()
              tnfull <- toFullNames tn
              let code : Integer = 2 + 256 * cast (length fields) + 16777216 * cast tag
              let ty = Ref fc (TyCon tyArity) tn
              let layout = apply fc (Ref fc (DataCon ltag lar) mkLayout)
                                 [ty, PrimVal fc (B64 (cast code))]
              let val = apply fc (Ref fc (DataCon ftag far) mkFlat) [ty, layout]
              let hty = App fc (Ref fc (TyCon 1) flat) ty
              let hn = NS (currentNS defs) (MN ("flat layout of " ++ show tnfull) 0)
              -- (the names resolved, as those of the elaborated terms are:
              -- the search compares them)
              val <- toResolvedNames val
              hty <- toResolvedNames hty
              let def = PMDef defaultPI Scope.empty (STerm 0 val) (STerm 0 val) []
              let gdef = { totality := MkTotality IsTerminating IsCovering }
                           (newDef fc hn top Scope.empty hty (specified Public) def)
              ignore $ addDef hn gdef
              addToSave hn
              setFlag fc hn Inline
              addHintFor fc flat hn True False
              log "declare.data.flat" 1 $ "Arrays of " ++ show tnfull ++ " are flat: " ++ show code
addFlatHint _ _ _ = pure ()
