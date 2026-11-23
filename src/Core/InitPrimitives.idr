module Core.InitPrimitives

import Compiler.CompileExpr

import Core.Context
import Core.Primitives

%default covering

addPrim : {auto c : Ref Ctxt Defs} ->
          Prim -> Core ()
addPrim p
    = do addBuiltin (opName (fn p)) (type p) (totality p) (fn p)
         compileDef (opName (fn p))

||| Add the primitives to the context, which is new: the first time they are
||| made and compiled, and what that gives is kept (in `primDefs`) for the
||| next times, the context being cleared for each module that is built.
export
addPrimitives : {auto c : Ref Ctxt Defs} -> Core ()
addPrimitives
    = case primDefs !(get Ctxt) of
           [] => do traverse_ addPrim allPrimitives
                    defs <- get Ctxt
                    ds <- traverse (\ p => made defs (opName (fn p))) allPrimitives
                    update Ctxt { primDefs := ds }
           ds => traverse_ (\ (n, d) => ignore $ addDef n d) ds
  where
    made : Defs -> Name -> Core (Name, GlobalDef)
    made defs n
        = do Just d <- lookupCtxtExact n (gamma defs)
               | Nothing => throw (InternalError ("No primitive " ++ show n))
             pure (n, d)
