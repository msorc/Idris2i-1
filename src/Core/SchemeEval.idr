module Core.SchemeEval

-- Top level interface to the scheme based evaluator
-- Drops back to the default slow evaluator if scheme isn't available

import Core.Context
import Core.Env
import Core.Normalise
import public Core.SchemeEval.Compile
import public Core.SchemeEval.Evaluate
import public Core.SchemeEval.Quote
import public Core.SchemeEval.ToScheme

{-

Summary:

SObj vars
   ...is a scheme object with the scheme representation of the result
   of evaluating a term vars

SNF vars
   ...corresponds to NF vars, and is an inspectable version of the above.
   Evaluation is call by value, but there has not yet been any evaluation
   under lambdas

'Evaluate.seval' gets you an SObj from a Term
   - this involves compiling all the relevant definitions to scheme code
   first. We make a note of what we've compiled to scheme so we don't have
   to do it more than once.
`Evaluate.toSNF` gets you an SNF from an SObj
`Quote.quote` gets you back to a Term from an SNF

`snf` gets you directly to an SNF from a Term
`snormalise` packages up the whole process

All of this works only on a back end which can call scheme directly, and
with the relevant support files (currently: Chez)

-}

snormaliseMode : {auto c : Ref Ctxt Defs} ->
                 {vars : _} ->
                 SchemeMode -> Env Term vars -> Term vars -> Core (Term vars)
snormaliseMode mode env tm
    = do defs <- get Ctxt
         True <- initialiseSchemeEval
             | _ => normalise defs env tm
         sval <- seval mode env tm
         quoteObj sval

export
snormalise : {auto c : Ref Ctxt Defs} ->
             {vars : _} ->
             Env Term vars -> Term vars -> Core (Term vars)
snormalise = snormaliseMode BlockExport

export
snormaliseAll : {auto c : Ref Ctxt Defs} ->
                {vars : _} ->
                Env Term vars -> Term vars -> Core (Term vars)
snormaliseAll = snormaliseMode EvalAll

-- The error when the Scheme evaluator cannot be used.  The compiler either
-- does not run on a Scheme system that it supports (it is compiled with
-- RefC, say), or it does but the support code of the evaluator could not be
-- loaded, which is a fault: the test suite (tests/Main.idr) skips the tests
-- of the evaluator in the first case only, so the messages must differ.
schemeEvalUnavailable : Core a
schemeEvalUnavailable
    = throw $ InternalError $
        if schemeEvalHost
           then "Scheme evaluator could not be loaded"
           else "Scheme evaluator not available"

export
snf : {auto c : Ref Ctxt Defs} ->
      {vars : _} ->
      Env Term vars -> Term vars -> Core (SNF vars)
snf env tm
    = do True <- initialiseSchemeEval
             | _ => schemeEvalUnavailable
         sval <- seval BlockExport env tm
         toSNF sval

export
snfAll : {auto c : Ref Ctxt Defs} ->
         {vars : _} ->
         Env Term vars -> Term vars -> Core (SNF vars)
snfAll env tm
    = do True <- initialiseSchemeEval
             | _ => schemeEvalUnavailable
         sval <- seval EvalAll env tm
         toSNF sval
