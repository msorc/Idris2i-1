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

import Core.CompileExpr
import Core.Context
import Core.Env
import Core.Normalise
import Core.Value

import Libraries.Data.NatSet

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
