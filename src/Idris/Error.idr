module Idris.Error

import Core.AutoSearch
import Core.Coverage
import Core.Value
import Core.Directory
import Core.Termination.CallGraph
import Core.Env

import Idris.Doc.String
import Idris.ErrorCode
import Idris.REPL.Opts
import Idris.Resugar
import Idris.Syntax
import Idris.Syntax.TTC
import Idris.Pretty

import Data.List
import Data.Either
import Data.List1
import Data.String

import Libraries.Data.ANameMap
import Libraries.Data.List.Extra
import Libraries.Data.NameMap
import Libraries.Data.NatSet
import Libraries.Data.WithDefault
import Libraries.Data.StringMap
import Libraries.Text.PrettyPrint.Prettyprinter.Util

import System.Clock
import System.Directory
import System.File
import Libraries.Utils.Path

%default covering

-- Not fully correct, see e.g. `UnreachableClause` where we don't check the
-- Envs & Terms because we don't yet have equality instances for these
export
Eq Warning where
  ParserWarning fc1 x1 == ParserWarning fc2 x2 = fc1 == fc2 && x1 == x2
  UnreachableClause fc1 rho1 s1 == UnreachableClause fc2 rho2 s2 = fc1 == fc2
  ShadowingGlobalDefs fc1 xs1 == ShadowingGlobalDefs fc2 xs2 = fc1 == fc2 && xs1 == xs2
  IncompatibleVisibility fc1 x1 y1 n1 == IncompatibleVisibility fc2 x2 y2 n2
    = fc1 == fc2 && x1 == x2 && y1 == y2 && n1 == n2
  Deprecated fc1 x1 y1 == Deprecated fc2 x2 y2 = fc1 == fc2 && x1 == x2 && y1 == y2
  GenericWarn fc1 x1 == GenericWarn fc2 x2 = fc1 == fc2 && x1 == x2
  ErrorWarning err1 == ErrorWarning err2 = getErrorLoc err1 == getErrorLoc err2
  _ == _ = False

export
Eq TTCErrorMsg where
  Format x1 y1 z1 == Format x2 y2 z2 = x1 == x2 && y1 == y2 && z1 == z2
  EndOfBuffer x1 == EndOfBuffer x2 = x1 == x2
  Corrupt x1 == Corrupt x2 = x1 == x2
  _ == _ = False

export
Eq FileError where
  GenericFileError x1 == GenericFileError x2 = x1 == x2
  FileReadError == FileReadError = True
  FileWriteError == FileWriteError = True
  FileNotFound == FileNotFound = True
  PermissionDenied == PermissionDenied = True
  FileExists == FileExists = True
  _ == _ = False

-- Not fully correct, see e.g. `CantConvert` where we don't check the Env
export
Eq Error where
  Fatal err1 == Fatal err2 = err1 == err2
  CantConvert fc1 gam1 rho1 s1 t1 == CantConvert fc2 gam2 rho2 s2 t2 = fc1 == fc2
  CantSolveEq fc1 gam1 rho s1 t1 _ == CantSolveEq fc2 gam2 rho2 s2 t2 _ = fc1 == fc2
  PatternVariableUnifies fc1 fct1 rho1 n1 s1 == PatternVariableUnifies fc2 fct2 rho2 n2 s2 = fc1 == fc2 && fct1 == fct2 && n1 == n2
  CyclicMeta fc1 rho1 n1 s1 == CyclicMeta fc2 rho2 n2 s2 = fc1 == fc2 && n1 == n2
  WhenUnifying fc1 o1 gam1 rho1 s1 t1 _ err1 == WhenUnifying fc2 o2 gam2 rho2 s2 t2 _ err2 = fc1 == fc2 && o1 == o2 && err1 == err2
  ValidCase fc1 rho1 x1 == ValidCase fc2 rho2 x2 = fc1 == fc2
  UndefinedName fc1 n1 == UndefinedName fc2 n2 = fc1 == fc2 && n1 == n2
  InvisibleName fc1 n1 x1 == InvisibleName fc2 n2 x2 = fc1 == fc2 && n1 == n2 && x1 == x2
  BadTypeConType fc1 n1 == BadTypeConType fc2 n2 = fc1 == fc2 && n1 == n2
  BadDataConType fc1 n1 m1 == BadDataConType fc2 n2 m2 = fc1 == fc2 && n1 == n2 && m1 == m2
  NotCovering fc1 n1 x1 == NotCovering fc2 n2 x2 = fc1 == fc2 && n1 == n2
  NotTotal fc1 n1 x1 == NotTotal fc2 n2 x2 = fc1 == fc2 && n1 == n2
  LinearUsed fc1 k1 n1 == LinearUsed fc2 k2 n2 = fc1 == fc2 && k1 == k2 && n1 == n2
  LinearMisuse fc1 n1 x1 y1 == LinearMisuse fc2 n2 x2 y2 = fc1 == fc2 && n1 == n2 && x1 == x2 && y1 == y2
  BorrowPartial fc1 rho1 s1 t1 == BorrowPartial fc2 rho2 s2 t2 = fc1 == fc2
  BorrowPartialType fc1 rho1 s1 == BorrowPartialType fc2 rho2 s2 = fc1 == fc2
  AmbiguousName fc1 xs1 == AmbiguousName fc2 xs2 = fc1 == fc2 && xs1 == xs2
  AmbiguousElab fc1 rho1 xs1 == AmbiguousElab fc2 rho2 xs2 = fc1 == fc2
  AmbiguousSearch fc1 rho1 s1 xs1 == AmbiguousSearch fc2 rho2 s2 xs2 = fc1 == fc2
  AmbiguityTooDeep fc1 n1 xs1 == AmbiguityTooDeep fc2 n2 xs2 = fc1 == fc2 && n1 == n2 && xs1 == xs2
  AllFailed fc1 xs1 == AllFailed fc2 xs2 = fc1 == fc2 && assert_total (xs1 == xs2)
  RecordTypeNeeded fc1 rho1 == RecordTypeNeeded fc2 rho2 = fc1 == fc2
  DuplicatedRecordUpdatePath fc1 xs1 == DuplicatedRecordUpdatePath fc2 xs2 = fc1 == fc2 && xs1 == xs2
  NotRecordField fc1 x1 y1 == NotRecordField fc2 x2 y2 = fc1 == fc2 && x1 == x2 && y1 == y2
  NotRecordType fc1 n1 == NotRecordType fc2 n2 = fc1 == fc2 && n1 == n2
  IncompatibleFieldUpdate fc1 xs1 == IncompatibleFieldUpdate fc2 xs2 = fc1 == fc2 && xs1 == xs2
  InvalidArgs fc1 rho1 xs1 s1 == InvalidArgs fc2 rho2 xs2 s2 = fc1 == fc2
  TryWithImplicits fc1 rho1 xs1 == TryWithImplicits fc2 rho2 xs2 = fc1 == fc2
  BadUnboundImplicit fc1 rho1 n1 s1 == BadUnboundImplicit fc2 rho2 n2 s2 = fc1 == fc2 && n1 == n2
  CantSolveGoal fc1 gam1 rho1 s1 x1 == CantSolveGoal fc2 gam2 rho2 s2 x2 = fc1 == fc2
  SearchNeeds fc1 _ n1 _ _ _ _ == SearchNeeds fc2 _ n2 _ _ _ _ = fc1 == fc2 && n1 == n2
  DeterminingArg fc1 n1 x1 rho1 s1 == DeterminingArg fc2 n2 x2 rho2 s2 = fc1 == fc2 && n1 == n2 && x1 == x2
  UnsolvedHoles xs1 == UnsolvedHoles xs2 = xs1 == xs2
  CantInferArgType fc1 rho1 n1 m1 s1 == CantInferArgType fc2 rho2 n2 m2 s2 = fc1 == fc2 && n1 == n2 && m1 == m2
  SolvedNamedHole fc1 rho1 n1 s1 == SolvedNamedHole fc2 rho2 n2 s2 = fc1 == fc2 && n1 == n2
  VisibilityError fc1 x1 n1 y1 m1 == VisibilityError fc2 x2 n2 y2 m2
    = fc1 == fc2 && x1 == x2 && n1 == n2 && y1 == y2 && m1 == m2
  NonLinearPattern fc1 n1 == NonLinearPattern fc2 n2 = fc1 == fc2 && n1 == n2
  BadPattern fc1 n1 == BadPattern fc2 n2 =  fc1 == fc2 && n1 == n2
  NoDeclaration fc1 n1 == NoDeclaration fc2 n2 = fc1 == fc2 && n1 == n2
  AlreadyDefined fc1 n1 == AlreadyDefined fc2 n2 = fc1 == fc2 && n1 == n2
  NotFunctionType fc1 rho1 s1 == NotFunctionType fc2 rho2 s2 = fc1 == fc2
  RewriteNoChange fc1 rho1 s1 t1 == RewriteNoChange fc2 rho2 s2 t2 = fc1 == fc2
  NotRewriteRule fc1 rho1 s1 == NotRewriteRule fc2 rho2 s2 = fc1 == fc2
  CaseCompile fc1 n1 x1 == CaseCompile fc2 n2 x2 = fc1 == fc2 && n1 == n2
  MatchTooSpecific fc1 rho1 s1 == MatchTooSpecific fc2 rho2 s2 = fc1 == fc2
  LiteralNotMatchable fc1 _ l1 n1 _ == LiteralNotMatchable fc2 _ l2 n2 _
    = fc1 == fc2 && l1 == l2 && n1 == n2
  BadDotPattern fc1 rho1 x1 s1 t1 == BadDotPattern fc2 rho2 x2 s2 t2 = fc1 == fc2
  BadImplicit fc1 x1 == BadImplicit fc2 x2 = fc1 == fc2 && x1 == x2
  BadRunElab fc1 rho1 s1 d1 == BadRunElab fc2 rho2 s2 d2 = fc1 == fc2 && d1 == d2
  RunElabFail e1 == RunElabFail e2 = e1 == e2
  GenericMsg fc1 x1 == GenericMsg fc2 x2 = fc1 == fc2 && x1 == x2
  GenericMsgSol fc1 x1 y1 z1 == GenericMsgSol fc2 x2 y2 z2 = fc1 == fc2 && x1 == x2 && y1 == y2 && z1 == z2
  GenericMsgTerm fc1 _ x1 _ y1 == GenericMsgTerm fc2 _ x2 _ y2 = fc1 == fc2 && x1 == x2 && y1 == y2
  TTCError x1 == TTCError x2 = x1 == x2
  FileErr x1 y1 == FileErr x2 y2 = x1 == x2 && y1 == y2
  CantFindPackage x1 == CantFindPackage x2 = x1 == x2
  LitFail fc1 == LitFail fc2 = fc1 == fc2
  LexFail fc1 x1 == LexFail fc2 x2 = fc1 == fc2 && x1 == x2
  ParseFail xs1 == ParseFail xs2 = xs1 == xs2
  ModuleNotFound fc1 x1 == ModuleNotFound fc2 x2 = fc1 == fc2 && x1 == x2
  CyclicImports xs1 == CyclicImports xs2 = xs1 == xs2
  ForceNeeded == ForceNeeded = True
  InternalError x1 == InternalError x2 = x1 == x2
  UserError x1 == UserError x2 = x1 == x2
  NoForeignCC fc1 xs1 == NoForeignCC fc2 xs2 = fc1 == fc2 && xs1 == xs2
  BadMultiline fc1 x1 == BadMultiline fc2 x2 = fc1 == fc2 && x1 == x2
  Timeout x1 == Timeout x2 = x1 == x2
  FailingDidNotFail fc1 == FailingDidNotFail fc2 = fc1 == fc2
  FailingWrongError fc1 x1 err1 == FailingWrongError fc2 x2 err2
    = fc1 == fc2 && x1 == x2 && assert_total (err1 == err2)
  InType fc1 n1 err1 == InType fc2 n2 err2 = fc1 == fc2 && n1 == n2 && err1 == err2
  InCon n1 err1 == InCon n2 err2 = n1 == n2 && err1 == err2
  InLHS fc1 n1 err1 == InLHS fc2 n2 err2 = fc1 == fc2 && n1 == n2 && err1 == err2
  InRHS fc1 n1 err1 == InRHS fc2 n2 err2 = fc1 == fc2 && n1 == n2 && err1 == err2
  MaybeMisspelling err1 xs1 == MaybeMisspelling err2 xs2 = err1 == err2 && xs1 == xs2
  QuantitiesChosen fc1 n1 _ err1 == QuantitiesChosen fc2 n2 _ err2 = fc1 == fc2 && n1 == n2 && err1 == err2
  WarningAsError wrn1 == WarningAsError wrn2 = wrn1 == wrn2
  _ == _ = False

keyword : Doc IdrisAnn -> Doc IdrisAnn
keyword = annotate (Syntax Keyword)

||| Label of the pattern variables met while printing a missing case.
data PatVars : Type where

||| Label of the state kept while one message is printed: the local variables
||| and metavariables printed so far, and new names for those that would
||| print like another one (see `distinctNames`).
data MsgNames : Type where

record MsgNameState where
  constructor MkMsgNames
  -- how each variable prints, and the variable, in the order they appear
  locals : List (String, Name)
  -- how each metavariable prints, and the metavariable
  metas : List (String, Int)
  -- the names to use instead
  localNames : List (Name, String)
  metaNames : List (Int, String)
  -- the definitions the message is about, which are not suggested as
  -- spellings of an undefined name
  defining : List Name

initMsgNames : MsgNameState
initMsgNames = MkMsgNames [] [] [] [] []

||| How a local variable prints once machine generated names are tidied (as
||| `cleanPTerm` does).
tidiedName : Name -> String
tidiedName (PV n _) = tidiedName n
tidiedName (MN n _) = n
tidiedName (DN n _) = n
tidiedName (Nested _ n) = tidiedName n
tidiedName (NS _ n) = tidiedName n
tidiedName n = show n

||| The new names for different things that print alike. A variable the user
||| named keeps its name (or else the first one to appear does) and the others
||| get `{1}`, `{2}`, ... after it; metavariables, none of which was named by
||| the user, are all numbered. Braces cannot occur in a name in the source,
||| so the new names cannot be mistaken for other variables or holes.
clashes : MsgNameState -> (List (Name, String), List (Int, String))
clashes st
    = (concatMap localRenames (groups (reverse (locals st))),
       concatMap metaRenames (groups (reverse (metas st))))
  where
    groups : Eq a => List (String, a) -> List (String, List a)
    groups [] = []
    groups ((s, x) :: xs)
        = let (same, rest) = partition ((== s) . fst) xs in
              (s, nub (x :: map snd same)) :: groups (assert_smaller xs rest)

    numbered : String -> List a -> List (a, String)
    numbered s xs = zipWith (\ i, x => (x, s ++ "{" ++ show i ++ "}")) [1 .. length xs] xs

    userNamed : Name -> Bool
    userNamed (UN _) = True
    userNamed _ = False

    localRenames : (String, List Name) -> List (Name, String)
    localRenames (s, ns@(_ :: _ :: _))
        = case break userNamed ns of
               (before, kept :: after) => numbered s (before ++ after)
               _ => numbered s (drop 1 ns)
    localRenames _ = []

    metaRenames : (String, List Int) -> List (Int, String)
    metaRenames (s, is@(_ :: _ :: _)) = numbered s is
    metaRenames _ = []

||| Print a message so that different variables, or different metavariables,
||| that would print the same are told apart: print it once noting the names,
||| and if any clash, print it again with new names for them. The names are
||| only changed in this message.
distinctNames : {auto mnames : Ref MsgNames MsgNameState} ->
                Core a -> Core a
distinctNames act
    = do saved <- get MsgNames
         put MsgNames ({ locals := [], metas := [], localNames := [], metaNames := [] } saved)
         res <- act
         st <- get MsgNames
         res <- case clashes st of
                     ([], []) => pure res
                     (ls, ms) => do put MsgNames ({ locals := [], metas := []
                                                  , localNames := ls, metaNames := ms } saved)
                                    act
         put MsgNames saved
         pure res

||| Give each metavariable in a term a name that says which it is, so that
||| it can be recognised once the term is resugared (see `noteName`).
tagMetas : Term vars -> Term vars
tagMetas (Meta fc n i args)
    = Meta fc (UN (Basic (nameRoot n ++ "@" ++ show i))) i (map tagMetas args)
tagMetas (Bind fc x b sc) = Bind fc x (map tagMetas b) (tagMetas sc)
tagMetas (App fc f a) = App fc (tagMetas f) (tagMetas a)
tagMetas (As fc s a p) = As fc s (tagMetas a) (tagMetas p)
tagMetas (TDelayed fc r t) = TDelayed fc r (tagMetas t)
tagMetas (TDelay fc r t a) = TDelay fc r (tagMetas t) (tagMetas a)
tagMetas (TForce fc r t) = TForce fc r (tagMetas t)
tagMetas t = t

||| Note how a variable or a metavariable prints, and use its new name if it
||| has one.
noteName : {auto mnames : Ref MsgNames MsgNameState} ->
           IPTerm -> Core IPTerm
noteName (PHole fc b str)
    = do -- a metavariable on its own is followed by the variables in scope
         let (root, tagged) = break (== '@') (unpack str)
         let (idx, rest) = span isDigit (drop 1 tagged)
         let Just i = parseInteger {a = Int} (pack idx)
             | Nothing => pure (PHole fc b str)
         let root = pack root
         update MsgNames { metas $= ((root, i) ::) }
         st <- get MsgNames
         pure (PHole fc b (fromMaybe root (lookup i (metaNames st)) ++ pack rest))
noteName (PRef fc (MkKindedName (Just Bound) fn nm))
    = do -- anonymous pattern variables are all called `_` on purpose
         when (tidiedName nm /= "_") $
           update MsgNames { locals $= ((tidiedName nm, nm) ::) }
         st <- get MsgNames
         pure $ case lookup nm (localNames st) of
                     Just new => PRef fc (MkKindedName (Just Bound) fn (UN (Basic new)))
                     Nothing => PRef fc (MkKindedName (Just Bound) fn nm)
noteName (PPi fc rig info (Just x) arg ret)
    = do st <- get MsgNames
         pure $ case lookup x (localNames st) of
                     Just new => PPi fc rig info (Just (UN (Basic new))) arg ret
                     Nothing => PPi fc rig info (Just x) arg ret
noteName tm = pure tm

||| Resugar a term to print in a message (see `distinctNames`).
resugarMsg : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto s : Ref Syn SyntaxInfo} ->
             {auto mnames : Ref MsgNames MsgNameState} ->
             Env Term vars -> Term vars -> Core IPTerm
resugarMsg env tm
    = if showMachineNames !getPPrint
         then resugar env tm
         else resugarWith noteName env (tagMetas tm)

-- | Add binding site information if the term is simply a machine-inserted name
pShowMN : {vars : _} -> Term vars -> Env t vars -> Doc IdrisAnn -> Doc IdrisAnn
pShowMN t env acc = case t of
  Local fc _ idx p => case dropAllNS (nameAt p) of
      MN {} => acc <++> parens ("implicitly bound at" <++> pretty0 (getBinderLoc p env))
      _ => acc
  _ => acc

pshow : {vars : _} ->
        {auto c : Ref Ctxt Defs} ->
        {auto s : Ref Syn SyntaxInfo} ->
        {auto mnames : Ref MsgNames MsgNameState} ->
        Env Term vars -> Term vars -> Core (Doc IdrisAnn)
pshow env tm
    = do defs <- get Ctxt
         ntm <- normaliseHoles defs env tm
         itm <- resugarMsg env ntm
         pure (pShowMN ntm env $ prettyBy Syntax itm)

||| Print a missing case so that it can be pasted back as a clause: a
||| variable that occurs once prints as `_`, and variables that occur more
||| than once get readable names that differ.
pshowPattern : {auto c : Ref Ctxt Defs} ->
               {auto s : Ref Syn SyntaxInfo} ->
               Term [] -> Core (Doc IdrisAnn)
pshowPattern tm
    = do defs <- get Ctxt
         ntm <- normaliseHoles defs Env.empty tm
         True <- not . showMachineNames <$> getPPrint
           | False => prettyBy Syntax <$> resugar Env.empty ntm
         seen <- newRef PatVars (the (List Name) [])
         ignore $ resugarWith count Env.empty ntm
         occs <- get PatVars
         let repeated = nub (filter (\ v => length (filter (== v) occs) > 1) (reverse occs))
         let names = rename repeated
         itm <- resugarWith (replace names) Env.empty ntm
         pure (prettyBy Syntax itm)
  where
    count : {auto r : Ref PatVars (List Name)} -> IPTerm -> Core IPTerm
    count tm@(PRef _ (MkKindedName (Just Bound) _ nm))
        = do update PatVars (nm ::); pure tm
    count tm = pure tm

    -- The variables that occur more than once keep their names where these
    -- differ, and are numbered from 1 where they do not
    rename : List Name -> List (Name, String)
    rename vs
        = map (\ v => (v, newName v)) vs
      where
        sameRoot : Name -> List Name
        sameRoot v = filter (\ w => tidiedName w == tidiedName v) vs

        newName : Name -> String
        newName v = case sameRoot v of
                         [_] => tidiedName v
                         ws => tidiedName v ++ show (S (length (takeWhile (/= v) ws)))

    replace : List (Name, String) -> IPTerm -> Core IPTerm
    replace names (PRef fc (MkKindedName (Just Bound) fn nm))
        = pure $ case lookup nm names of
                      Just new => PRef fc (MkKindedName (Just Bound) fn (UN (Basic new)))
                      Nothing => PImplicit fc
    replace names tm = pure tm

pshowNoNorm : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              {auto s : Ref Syn SyntaxInfo} ->
              {auto mnames : Ref MsgNames MsgNameState} ->
              Env Term vars -> Term vars -> Core (Doc IdrisAnn)
pshowNoNorm env tm
    = do defs <- get Ctxt
         itm <- resugarMsg env tm
         pure (pShowMN tm env $ prettyBy Syntax itm)

pairLine : {vars : _} ->
           {auto c : Ref Ctxt Defs} ->
           {auto s : Ref Syn SyntaxInfo} ->
           {auto mnames : Ref MsgNames MsgNameState} ->
           String -> Context -> Env Term vars -> Term vars -> Term vars ->
           Core (Doc IdrisAnn, (Doc IdrisAnn, Doc IdrisAnn))
pairLine msg gam env l r
    = do defs <- get Ctxt
         setCtxt gam
         ld <- pshow env l
         rd <- pshow env r
         put Ctxt defs
         pure (errorDesc (hsep [ reflow msg <+> colon, code ld, "and", code rd <+> dot ]),
               (ld, rd))

-- Source excerpts are left out of machine-readable (JSON) diagnostics, since
-- the location is reported separately there.
ploc : {auto c : Ref Ctxt Defs} ->
       {auto o : Ref ROpts REPLOpts} ->
       FC -> Core (Doc IdrisAnn)
ploc fc = do
    HumanErrors <- errorFormat <$> getSession
      | JSONErrors => pure emptyDoc
    let Just (fn, s, e) = isNonEmptyFC fc
        | Nothing => pure emptyDoc
    let (sr, sc) = mapHom (fromInteger . cast) s
    let (er, ec) = mapHom (fromInteger . cast) e
    let nsize = length $ show (er + 1)
    let head = annotate FileCtxt (pretty0 fc)
    source <- lines <$> getCurrentElabSource
    if sr == er
       then do
         let emph = spaces (cast $ nsize + sc + 4) <+> annotate Error (pretty0 (replicate (ec `minus` sc) '^'))
         let firstr = er `minus` 4
         pure $ vsep ([emptyDoc, head] ++ (addLineNumbers nsize firstr (pretty0 <$> extractRange firstr er source)) ++ [emph]) <+> line
       else do
         -- A span of several lines: mark where it starts on the first line
         -- and where it ends on the last, and leave out the middle of a
         -- long one
         let srcLine : Nat -> String
             srcLine r = fromMaybe "" (elemAt source r)
         let firstEnd = max (S sc) (length (dropWhile isSpace (reverse (unpack (srcLine sr)))))
         let lastStart = min (length (takeWhile isSpace (unpack (srcLine er)))) (ec `minus` 1)
         let mark : Nat -> Nat -> Doc IdrisAnn
             mark from to = spaces (cast $ nsize + from + 4)
                              <+> annotate Error (pretty0 (String.replicate (to `minus` from) '^'))
         let numbered : Nat -> Nat -> List (Doc IdrisAnn)
             numbered from to = addLineNumbers nsize from (pretty0 <$> extractRange from to source)
         -- (a line that is not in the source is not marked)
         let marked : List (Doc IdrisAnn) -> Doc IdrisAnn -> List (Doc IdrisAnn)
             marked [] _ = []
             marked ls m = ls ++ [m]
         let first = marked (numbered sr sr) (mark sc firstEnd)
         let last = marked (numbered er er) (mark lastStart ec)
         let body = if (er `minus` sr) < 6
                       then first ++ (if er > S sr then numbered (S sr) (er `minus` 1) else [])
                            ++ last
                       else first ++ numbered (S sr) (S sr)
                            ++ (if null (numbered (S sr) (S sr)) then []
                                   else [space <+> annotate FileCtxt (pretty0 (String.replicate nsize '.') <++> pipe)])
                            ++ numbered (er `minus` 1) (er `minus` 1) ++ last
         pure $ vsep (emptyDoc :: head :: body) <+> line
  where
    extractRange : Nat -> Nat -> List String -> List String
    extractRange s e xs = take ((e `minus` s) + 1) (drop s xs)
    pad : Nat -> String -> String
    pad size s = replicate (size `minus` length s) '0' ++ s
    addLineNumbers : Nat -> Nat -> List (Doc IdrisAnn) -> List (Doc IdrisAnn)
    addLineNumbers size st xs =
      snd $ foldl (\(i, s), l => (S i, snoc s (space <+> annotate FileCtxt (pretty0 (pad size $ show $ i + 1) <++> pipe) <++> l))) (st, []) xs

-- Assumes the two FCs are sorted
ploc2 : {auto c : Ref Ctxt Defs} ->
        {auto o : Ref ROpts REPLOpts} ->
        FC -> FC -> Core (Doc IdrisAnn)
ploc2 fc1 fc2 =
    do HumanErrors <- errorFormat <$> getSession
         | JSONErrors => pure emptyDoc
       let Just (fn1, s1, e1) = isNonEmptyFC fc1
           | Nothing => ploc fc2
       let Just (fn2, s2, e2) = isNonEmptyFC fc2
           | Nothing => ploc fc1
       let (sr1, sc1) = mapHom (fromInteger . cast) s1
       let (sr2, sc2) = mapHom (fromInteger . cast) s2
       let (er1, ec1) = mapHom (fromInteger . cast) e1
       let (er2, ec2) = mapHom (fromInteger . cast) e2
       if (er2 > the Nat (er1 + 5))
          then pure $ !(ploc (MkFC fn1 s1 e1)) <+> line <+> !(ploc (MkFC fn2 s2 e2))
          else do let nsize = length $ show (er2 + 1)
                  let head = annotate FileCtxt (pretty0 $ MkFC fn1 s1 e2)
                  let firstRow = annotate FileCtxt (spaces (cast $ nsize + 2) <+> pipe)
                  source <- lines <$> getCurrentElabSource
                  case (sr1 == er1, sr2 == er2, sr1 == sr2) of
                       (True, True, True) => do
                         let line = fileCtxt pipe <++> maybe emptyDoc pretty0 (elemAt source sr1)
                         let emph = fileCtxt pipe <++> spaces (cast sc1) <+> error (pretty0 (replicate (ec1 `minus` sc1) '^'))
                                      <+> spaces (cast $ sc2 `minus` ec1) <+> error (pretty0 (replicate (ec2 `minus` sc2) '^'))
                         pure $ vsep [emptyDoc, head, firstRow, fileCtxt (space <+> byShow (sr1 + 1)) <++> align (vsep [line, emph]), emptyDoc]
                       (True, True, False) => do
                         let line1 = fileCtxt pipe <++> maybe emptyDoc pretty0 (elemAt source sr1)
                         let emph1 = fileCtxt pipe <++> spaces (cast sc1) <+> error (pretty0 (replicate (ec1 `minus` sc1) '^'))
                         let line2 = fileCtxt pipe <++> maybe emptyDoc pretty0 (elemAt source sr2)
                         let emph2 = fileCtxt pipe <++> spaces (cast sc2) <+> error (pretty0 (replicate (ec2 `minus` sc2) '^'))
                         let numbered = if (sr2 `minus` er1) == 1
                                           then []
                                           else addLineNumbers nsize (sr1 + 1) (pretty0 <$> extractRange (sr1 + 1) er1 source)
                         pure $ vsep $ [emptyDoc, head, firstRow, fileCtxt (space <+> byShow (sr1 + 1)) <++> align (vsep [line1, emph1])]
                            ++ numbered
                            ++ [fileCtxt (space <+> byShow (sr2 + 1)) <++> align (vsep [line2, emph2]), emptyDoc]
                       (True, False, _) => do
                         let line = fileCtxt pipe <++> maybe emptyDoc pretty0 (elemAt source sr1)
                         let emph = fileCtxt pipe <++> spaces (cast sc1) <+> error (pretty0 (replicate (ec1 `minus` sc1) '^'))
                         pure $ vsep $ [emptyDoc, head, firstRow, fileCtxt (space <+> byShow (sr1 + 1)) <++> align (vsep [line, emph])]
                            ++ addLineNumbers nsize (sr1 + 1) (pretty0 <$> extractRange (sr1 + 1) (Prelude.max er1 er2) source)
                            ++ [emptyDoc]
                       (False, True, True) => do
                         let line = fileCtxt pipe <++> maybe emptyDoc pretty0 (elemAt source sr1)
                         let emph = fileCtxt pipe <++> spaces (cast sc1) <+> error (pretty0 (replicate (ec1 `minus` sc1) '^'))
                         pure $ vsep $ [emptyDoc, head, firstRow, fileCtxt (space <+> byShow (sr1 + 1)) <++> align (vsep [line, emph])]
                            ++ addLineNumbers nsize (sr1 + 1) (pretty0 <$> extractRange (sr1 + 1) (Prelude.max er1 er2) source)
                            ++ [emptyDoc]
                       (False, True, False) => do
                         let top = addLineNumbers nsize (sr1 + 1) (pretty0 <$> extractRange (sr1 + 1) er1 source)
                         let line = fileCtxt pipe <++> maybe emptyDoc pretty0 (elemAt source sr1)
                         let emph = fileCtxt pipe <++> spaces (cast sc2) <+> error (pretty0 (replicate (ec2 `minus` sc2) '^'))
                         pure $ vsep $ [emptyDoc, head, firstRow] ++ top ++ [fileCtxt (space <+> byShow (sr2 + 1)) <++> align (vsep [line, emph]), emptyDoc]
                       (_, _, _) => pure $ vsep (emptyDoc :: head :: addLineNumbers nsize sr1 (pretty0 <$> extractRange sr1 er2 source)) <+> line
  where
    extractRange : Nat -> Nat -> List String -> List String
    extractRange s e xs = take ((e `minus` s) + 1) (drop s xs)
    pad : Nat -> String -> String
    pad size s = replicate (size `minus` length s) '0' ++ s
    addLineNumbers : Nat -> Nat -> List (Doc IdrisAnn) -> List (Doc IdrisAnn)
    addLineNumbers size st xs =
      snd $ foldl (\(i, s), l => (S i, snoc s (space <+> annotate FileCtxt (pretty0 (pad size $ show $ i + 1) <++> pipe) <++> l))) (st, []) xs

perrorRaw : {auto c : Ref Ctxt Defs} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto o : Ref ROpts REPLOpts} ->
            {auto mnames : Ref MsgNames MsgNameState} ->
            Error -> Core (Doc IdrisAnn)

||| A definition named in the details of a message. Machine generated names
||| (e.g. for `where` blocks) are unreadable, so tidy those, but otherwise
||| print the name in full, as the reason of a totality error does.
defName : {auto c : Ref Ctxt Defs} -> Name -> Core (Doc IdrisAnn)
defName n@(NS _ (Nested {})) = pretty0 <$> prettyName n
defName n@(Nested {}) = pretty0 <$> prettyName n
defName n = pure (pretty0 n)

||| The name of a definition in the headline of a message whose details name
||| other definitions in full: in full too if the details mention it, so that
||| it is printed in one form in the message, and as the user wrote it
||| otherwise.
headlineName : {auto c : Ref Ctxt Defs} ->
               Name -> List Name -> Core (Doc IdrisAnn)
headlineName n others
    = if n `elem` others then defName n else pretty0 <$> prettyName n

||| Render the message about an error found in a definition, which is not
||| suggested as a spelling of an undefined name in it.
inDefinition : {auto mnames : Ref MsgNames MsgNameState} ->
               Name -> Core a -> Core a
inDefinition def act
    = do st <- get MsgNames
         put MsgNames ({ defining $= (def ::) } st)
         res <- act
         update MsgNames { defining := defining st }
         pure res

pwarningRaw : {auto c : Ref Ctxt Defs} ->
              {auto s : Ref Syn SyntaxInfo} ->
              {auto o : Ref ROpts REPLOpts} ->
              {auto mnames : Ref MsgNames MsgNameState} ->
              Warning -> Core (Doc IdrisAnn)
pwarningRaw (ParserWarning fc msg)
    = pure $ pretty0 msg <+> line <+> !(ploc fc)
pwarningRaw (UnreachableClause fc env tm)
    = pure $ errorDesc (reflow "Unreachable clause:"
        <++> code !(pshow env tm))
        <+> line <+> !(ploc fc)
pwarningRaw (ShadowingGlobalDefs fc ns)
    = pure $ vcat
    $ reflow "We are about to implicitly bind the following lowercase names."
   :: reflow "You may be unintentionally shadowing the associated global definitions:"
   :: map pshadowing (forget ns)
   `snoc` !(ploc fc)
  where
    pshadowing : (Name, List1 Name) -> Doc IdrisAnn
    pshadowing (n, ns) = indent 2 $ hsep $
                           pretty0 n
                        :: reflow "is shadowing"
                        :: punctuate comma (map pretty0 (forget ns))

pwarningRaw (IncompatibleVisibility fc vx vy n)
    = pure $ warning (code (pretty0 (sugarName n))
        <++> reflow "has been forward-declared with"
        <++> keyword (pretty0 vx) <++> reflow "visibility, cannot change to"
        <++> keyword (pretty0 vy) <+> reflow ". This will be an error in a later release.")
        <+> line <+> !(ploc fc)

pwarningRaw (ShadowingLocalBindings fc ns)
    = pure $ vcat
    [ reflow "You may be unintentionally shadowing the following local bindings:"
    , indent 2 $ concatWith (surround (comma <+> space)) $ map (code . pretty0 . fst) $ forget ns
    , !(ploc fc)
    ]

pwarningRaw (Deprecated fc s fcAndName)
    = do docs <- traverseOpt (\(fc, name) => getDocsForName fc name justUserDoc) fcAndName
         pure . vsep $ catMaybes [ Just $ "Deprecation warning:" <++> pretty0 s
                                 , reAnnotate (const Pretty.UserDocString) <$> docs
                                 ]
pwarningRaw (WhereRecompute fc n outer deps)
    = pure $ vcat
    [ code (pretty0 (localName n))
        <++> reflow "is a local definition without arguments that uses"
        <++> concatWith (surround (comma <+> space))
               (map (code . pretty0 . localName) (forget deps))
        <++> reflow "from" <++> code (pretty0 (localName outer))
        <+> reflow ", so it is recomputed at each use. If it is expensive, bind it with"
        <++> code "let" <++> reflow "and pass it on."
    , !(ploc fc)
    ]
  where
    localName : Name -> String
    localName nm = case dropNS nm of
      Nested _ nm' => localName nm'
      nm' => sugarName nm'
pwarningRaw (GenericWarn fc s)
    = pure $ vcat [pretty0 s, !(ploc fc)]
pwarningRaw (ErrorWarning err)
    = perrorRaw !(toFullNames err)

export
pwarning : {auto c : Ref Ctxt Defs} ->
           {auto s : Ref Syn SyntaxInfo} ->
           {auto o : Ref ROpts REPLOpts} ->
           Warning -> Core (Doc IdrisAnn)
pwarning wrn
    = do mnames <- newRef MsgNames initMsgNames
         distinctNames (pwarningRaw !(toFullNames wrn))

||| The modules of the TTC files under the build or package directory `dir`,
||| with the paths of the files. The hint at an import looks at them for each
||| undefined name, so they are kept in `ttcDirs` while no directory under
||| `dir` changes (a file appearing in a directory or disappearing from it
||| changes the directory). The modification time of a directory changes at
||| the ticks of the clock of the file system, so a listing is kept only if
||| the directories had not changed for a few seconds when it was made.
||| The paths are made by appending the names of the entries, as parsing them
||| as paths took more time than the rest of the listing.
ttcModules : {auto c : Ref Ctxt Defs} ->
             String -> Core (List (String, String))
ttcModules dir
    = do defs <- get Ctxt
         let Just known = lookup dir (ttcDirs defs)
             | Nothing => list
         if !(allM unchanged (dirs known))
            then pure (modules known)
            else list
  where
    unchanged : (String, Timestamp) -> Core Bool
    unchanged (d, time) = pure (!(modTime d) == time)

    sep : String
    sep = singleton dirSeparator

    moduleName : String -> List String -> String
    moduleName file ns = joinBy "." (reverse (fst (splitExtensions file) :: ns))

    -- the files and the subdirectories in a directory, each in the reverse
    -- of the order in which they are read
    entries : String -> Directory -> List String -> List String ->
              IO (List String, List String)
    entries path d files subs
        = case !(nextDirEntry d) of
               Right (Just e) =>
                 if e == "." || e == ".."
                    then entries path d files subs
                    else do Right sub <- openDir (path ++ sep ++ e)
                              | Left _ => entries path d (e :: files) subs
                            closeDir sub
                            entries path d files (e :: subs)
               _ => pure (files, subs)

    -- the directory `path` and the directories under it, each with its
    -- modification time from before it was read, and the TTC files in them
    -- with the names of their modules (`ns` is the namespace of `path`,
    -- reversed)
    walk : String -> List String ->
           Core (List (String, Timestamp), List (String, String))
    walk path ns
        = do time <- modTime path
             Right d <- coreLift $ openDir path
               | Left _ => pure ([(path, time)], [])
             (files, subs) <- coreLift $ entries path d [] []
             coreLift $ closeDir d
             let here = map (\ f => (moduleName f ns, path ++ sep ++ f))
                            (filter (isSuffixOf ".ttc") files)
             below <- traverse (\ s => walk (path ++ sep ++ s) (s :: ns)) subs
             pure ((path, time) :: concatMap fst below,
                   here ++ concatMap snd below)

    settled : Clock UTC -> (String, Timestamp) -> Bool
    settled now (_, time) = time.sec > 0 && cast time.sec + 2 < seconds now

    list : Core (List (String, String))
    list = do (ds, mods) <- walk dir []
              now <- coreLift $ clockTime UTC
              update Ctxt { ttcDirs $= if all (settled now) ds
                                          then insert dir (MkTTCDir ds mods)
                                          else delete dir }
              pure mods

||| The modules in the build directory and in the packages in use that export
||| a definition called like the undefined name `n`, with the full names.
||| These modules are not loaded (or the name would not be undefined), so this
||| reads their TTC files; it only happens when the error is displayed.
importCandidates : {auto c : Ref Ctxt Defs} ->
                   Name -> Core (List (String, List Name))
importCandidates n
    = do let Just (Basic root) = userNameRoot n
             | _ => pure []
         bdir <- ttcBuildDirectory
         dirs <- extraSearchDirectories
         found <- traverse (inDir root) (nub (bdir :: dirs))
         -- an imported module that exports the name does not help: the name
         -- is hidden, or qualified with another namespace
         defs <- get Ctxt
         let imported = map (show . fst . snd) (allImported defs)
         let found = filter (\ (m, _) => not (m `elem` imported)) (concat found)
         -- a qualified name only matches definitions in that namespace
         let found = filter (\ (_, ns) => not (isNil ns)) $
                       map (\ (m, ns) => (m, filter (qualifiedLike n) ns)) found
         -- directories are listed in no particular order
         pure (sortBy (compare `on` fst) found)
  where
    qualifiedLike : Name -> Name -> Bool
    qualifiedLike (NS q _) (NS ns _) = q `isApproximationOf` ns
    qualifiedLike (NS q _) _ = False
    qualifiedLike _ _ = True

    inDir : String -> String -> Core (List (String, List Name))
    inDir root dir
        = do res <- for !(ttcModules dir) $ \ (m, file) =>
                      do ns <- exportedDefsNamed {extra = SyntaxInfo} file root
                         pure (m, ns)
             pure (filter (not . null . snd) res)

||| A hint to import a module, for an undefined name that another module
||| exports.
importHint : {auto c : Ref Ctxt Defs} ->
             Name -> Core (Doc IdrisAnn)
importHint n
    = case !(catch (importCandidates n) (\_ => pure [])) of
        [] => pure emptyDoc
        [(m, _)] => pure $ reflow "Suggestion:" <++> code (pretty0 m)
                      <++> reflow "exports" <++> code (pretty0 (nameRoot n))
                      <+> reflow "; add" <++> code ("import" <++> pretty0 m) <+> dot
                      <+> line
        ms => pure $ reflow "Suggestion:" <++> code (pretty0 (nameRoot n))
                <++> reflow "is exported by"
                <++> concatWith (surround (comma <+> space))
                       (map (code . pretty0 . fst) (take 5 ms))
                <+> (if length ms > 5 then comma <++> "..." else emptyDoc)
                <+> reflow "; import one of them" <+> dot
                <+> line

||| The termination checker can find a cycle of calls that goes round the
||| same calls more than once (`f -> g -> f -> g`): go round it once.
onceRound : PartialReason -> PartialReason
onceRound (RecPath loop)
    = -- the smallest rotation that leaves the cycle as it is is the length
      -- of the cycle once round
      case find (\ p => drop p loop ++ take p loop == loop) [1 .. length loop `minus` 1] of
           Just p => RecPath (take p loop)
           Nothing => RecPath loop
onceRound r = r

||| The calls in the definition of `n` of the functions `ns`, as recorded in
||| its size change graph, with the location of the name of the function
||| called.
callsTo : {auto c : Ref Ctxt Defs} ->
          Name -> List Name -> Core (List (FC, Name))
callsTo n ns
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact n (gamma defs)
           | Nothing => pure []
         calls <- traverse (\ c => map (fnLoc c,) (toFullNames (fnCall c)))
                           (sizeChange gdef)
         ns <- traverse toFullNames ns
         let dfc = location gdef
         case List.filter (after dfc) (List.filter (\ (_, cn) => cn `elem` ns) calls) of
              [] => -- not every call has a size change
                    List.filter (after dfc) <$> refsIn ns (the Nat 3) n
              found => pure found
  where
    -- The terms of a definition can have locations elsewhere (a type from
    -- another declaration): keep the calls that are in the definition
    after : FC -> (FC, Name) -> Bool
    after dfc (cfc, _)
        = case (isNonEmptyFC dfc, isNonEmptyFC cfc) of
               (Just (f, s, _), Just (f', s', _)) => f == f' && s <= s'
               _ => False

    refs : Term vs -> List (FC, Name)
    refs (Ref rfc _ rn) = [(rfc, rn)]
    refs (Meta _ _ _ args) = concatMap refs args
    refs (Bind _ _ b sc) = concatMap refs b ++ refs sc
    refs (App _ f a) = refs f ++ refs a
    refs (As _ _ a p) = refs p
    refs (TDelayed _ _ t) = refs t
    refs (TDelay _ _ t a) = refs a
    refs (TForce _ _ t) = refs t
    refs _ = []

    -- The references to `ns` in the right hand sides of the clauses of a
    -- definition, and of the case blocks in them
    refsIn : List Name -> Nat -> Name -> Core (List (FC, Name))
    refsIn ns Z _ = pure []
    refsIn ns (S k) d
        = do defs <- get Ctxt
             Just (PMDef _ _ _ _ cls) <- lookupDefExact d (gamma defs)
               | _ => pure []
             rs <- traverse (\ (rfc, rn) => map (rfc,) (toFullNames rn))
                            (concatMap (\ (_ ** (_, _, rhs)) => refs rhs) cls)
             let direct = filter (\ (_, rn) => rn `elem` ns) rs
             inner <- traverse (refsIn ns k . snd)
                               (nubBy (\ x, y => snd x == snd y)
                                      (filter (caseFn . snd) rs))
             pure (direct ++ concat inner)

||| The location of the first of some calls, if it is known and in the same
||| file as `fc`, and `fc` otherwise.
firstCallTo : FC -> List (FC, Name) -> FC
firstCallTo fc ((cfc, _) :: _)
    = case (isNonEmptyFC cfc, isNonEmptyFC fc) of
           (Just (f, _, _), Just (f', _, _)) => if f == f' then cfc else fc
           (Just _, Nothing) => cfc
           _ => fc
firstCallTo fc [] = fc

||| For each of the given non covering functions that is not covering because
||| of the methods of implementations (see `PartialMethods`), say which: the
||| name of an implementation does not say what is wrong with it.
implCoverageNotes : {auto c : Ref Ctxt Defs} ->
                    List Name -> Core (Doc IdrisAnn)
implCoverageNotes ns
    = do notes <- traverse note ns
         pure $ concatWith (<+>) (mapMaybe id notes)
  where
    note : Name -> Core (Maybe (Doc IdrisAnn))
    note fn
        = do defs <- get Ctxt
             Just gdef <- lookupCtxtExact fn (gamma defs)
                  | Nothing => pure Nothing
             let Just ms = partialMethods (flags gdef)
                  | Nothing => pure Nothing
             pure $ Just $ line <+> !(defName fn)
                    <++> reflow "is not covering, because of"
                    <++> concatWith (surround (comma <+> space)) (pretty0 <$> ms)

||| The expected and the actual type of an expression, labelled, one per line.
expectedGot : (exp, got : Doc IdrisAnn) -> Doc IdrisAnn
expectedGot exp got
    = indent 4 $ vsep [ "Expected:" <++> align (code exp)
                      , "Got:" <+> spaces 6 <+> align (code got) ]

||| For a constraint that was postponed and failed when it was retried, the
||| metavariables solved in the meantime, which made it fail.
inferredNote : {vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               {auto s : Ref Syn SyntaxInfo} ->
               {auto mnames : Ref MsgNames MsgNameState} ->
               Env Term vars -> List (Term vars, FC, Term vars) -> Core (Doc IdrisAnn)
inferredNote env [] = pure emptyDoc
inferredNote env inferred
    = do ds <- traverse solution (take 3 inferred)
         pure $ line <+> reflow "This was postponed, and failed after inferring"
                  <++> concatWith (surround (comma <+> space)) ds <+> dot <+> line
  where
    -- (the metavariable is printed as the others of the message, so that
    -- it is told apart from another one that would print alike)
    solution : (Term vars, FC, Term vars) -> Core (Doc IdrisAnn)
    solution (m, sfc, v)
        = do md <- pshowNoNorm env m
             -- without the variables in scope, which a metavariable on its
             -- own is printed with
             let name = trim (fst (break (== '[') (show md)))
             vd <- pshow env v
             pure $ meta (pretty0 name) <++> equals <++> code vd
                      <+> maybe emptyDoc (const (space <+> parens ("at" <++> annotate FileCtxt (pretty0 sfc))))
                                (isNonEmptyFC sfc)

||| The headline of an error about two terms ("Mismatch between: l and r."),
||| with the two terms as printed in it.
pairHeadline : {auto c : Ref Ctxt Defs} ->
               {auto s : Ref Syn SyntaxInfo} ->
               {auto mnames : Ref MsgNames MsgNameState} ->
               Error -> Core (Maybe (Doc IdrisAnn, (Doc IdrisAnn, Doc IdrisAnn)))
pairHeadline (CantConvert _ gam env l r)
    = Just <$> pairLine "Mismatch between" gam env l r
pairHeadline (CantSolveEq _ gam env l r _)
    = Just <$> pairLine "Can't solve constraint between" gam env l r
pairHeadline _ = pure Nothing

||| For display, we don't want to see the full top level type of a search
||| goal (which binds the local variables of where it was posted); just the
||| return type
dropEnv : {vars : _} ->
          Env Term vars -> Term vars ->
          (ns ** (Env Term ns, Term ns))
dropEnv env (Bind _ n b@(Pi {}) sc) = dropEnv (b :: env) sc
dropEnv env (Bind _ n b@(Let {}) sc) = dropEnv (b :: env) sc
dropEnv env tm = (_ ** (env, tm))

||| Where a definition named in a message is: in full if it is in the same
||| file as the error, and only its module otherwise, so that the message
||| does not change with the line numbers of a library.
defLoc : (errfc : FC) -> FC -> Doc IdrisAnn
defLoc errfc dfc
    = case (isNonEmptyFC errfc, isNonEmptyFC dfc) of
           (Just (o, _, _), Just (o', _, _)) =>
              if o == o' then "at" <++> annotate FileCtxt (pretty0 dfc)
                         else "in" <++> annotate FileCtxt (byShow o')
           (Nothing, Just (o', _, _)) => "in" <++> annotate FileCtxt (byShow o')
           _ => emptyDoc

||| Whether a name is that of an implementation without a name of its own
isUnnamedImpl : Name -> Bool
isUnnamedImpl (NS _ n) = isUnnamedImpl n
isUnnamedImpl (DN s _) = " implementation at " `isInfixOf` s
isUnnamedImpl _ = False

||| A hint (or a local variable) that a search tried, as the user would
||| recognise it: an implementation by its type, as it is declared
||| (`Show a => Show (List a)`), a named one or another hint by its name and
||| type, and where it is defined. Assumes the context the search failed in
||| is set.
candidateDesc : {auto c : Ref Ctxt Defs} ->
                {auto s : Ref Syn SyntaxInfo} ->
                {auto mnames : Ref MsgNames MsgNameState} ->
                (errfc : FC) -> Name -> (isLocal : Bool) -> Core (Doc IdrisAnn)
candidateDesc errfc n True
    = pure $ reflow "The local variable" <++> code (pretty0 (nameRoot n))
candidateDesc errfc n False
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact n (gamma defs)
           | Nothing => pure $ code (pretty0 n)
         pure $ reflow "The implementation" <++> !(hintDesc errfc gdef)
  where
    hintDesc : FC -> GlobalDef -> Core (Doc IdrisAnn)
    hintDesc errfc gdef
        = do ty <- pshow Env.empty (type gdef)
             let loc = defLoc errfc (location gdef)
             if isUnnamedImpl (fullname gdef)
                then pure $ code ty <++> parens loc
                else do nm <- prettyName (fullname gdef)
                        pure $ code (pretty0 nm <++> colon <++> ty) <++> parens loc

||| A global hint, in a list of them: an implementation by its type, a named
||| one or another hint by its name and type, and where it is defined
hintDesc : {auto c : Ref Ctxt Defs} ->
           {auto s : Ref Syn SyntaxInfo} ->
           {auto mnames : Ref MsgNames MsgNameState} ->
           (errfc : FC) -> GlobalDef -> Core (Doc IdrisAnn)
hintDesc errfc gdef
    = do ty <- pshow Env.empty (type gdef)
         let loc = defLoc errfc (location gdef)
         if isUnnamedImpl (fullname gdef)
            then pure $ code ty <++> parens ("implementation" <++> loc)
            else do nm <- prettyName (fullname gdef)
                    pure $ code (pretty0 nm <++> colon <++> ty) <++> parens loc

||| What a candidate of a chain of needed sub-goals is
data CandidateKind : Type where
  ||| The constructor of a pair, which a pair of constraints is split by
  PairCon : CandidateKind
  ||| The hint that gives an implementation of a parent interface from one
  ||| of the child interface
  ParentOf : (parent, child : Doc IdrisAnn) -> CandidateKind
  ImplCand : Doc IdrisAnn -> CandidateKind
  ConCand : Doc IdrisAnn -> CandidateKind
  HintCand : Doc IdrisAnn -> CandidateKind
  LocalCand : Doc IdrisAnn -> CandidateKind

||| A candidate of a chain, and the sub-goal it needs
record ChainLevel where
  constructor MkLevel
  kind : CandidateKind
  needs : Doc IdrisAnn

||| A pair of constraints is split into its two by the constructor of pairs:
||| the candidate before it needs the one of the two that failed
mergePairs : List ChainLevel -> List ChainLevel
mergePairs (MkLevel PairCon _ :: ls) = mergePairs ls
mergePairs (l :: MkLevel PairCon n :: ls) = mergePairs ({ needs := n } l :: ls)
mergePairs (l :: ls) = l :: mergePairs ls
mergePairs [] = []

startsWithParent : List ChainLevel -> Bool
startsWithParent (MkLevel (ParentOf _ _) _ :: _) = True
startsWithParent _ = False

levelLine : (first : Bool) -> ChainLevel -> Doc IdrisAnn
levelLine first (MkLevel (ParentOf p c) n)
    = code n <++> reflow "would give it, as" <++> code p <++> reflow "is a parent of"
        <++> code c <+> dot
levelLine first (MkLevel k n)
    = what k <++> (if first then "matches" else reflow "matches that")
        <+> comma <++> reflow "but needs" <++> code n <+> dot
  where
    what : CandidateKind -> Doc IdrisAnn
    what (ImplCand d) = reflow "The implementation" <++> d
    what (ConCand d) = reflow "The constructor" <++> d
    what (HintCand d) = reflow "The hint" <++> d
    what (LocalCand d) = reflow "The local variable" <++> d
    what _ = emptyDoc

||| Whether a name is that of a hint giving the implementation of a parent
||| interface (see `getConstraintHint` in `Idris.Elab.Interface`)
isParentHint : Name -> Bool
isParentHint (NS _ n) = isParentHint n
isParentHint (DN s _) = "Constraint " `isPrefixOf` s
isParentHint _ = False

||| The type constructor at the head of the return type of a type
retHead : Term vars -> Maybe Name
retHead (Bind _ _ (Pi {}) sc) = retHead sc
retHead tm = case getFn tm of
                  Ref _ (TyCon _) n => Just n
                  _ => Nothing

||| The type constructor at the head of the last explicit argument of a type
lastArgHead : Term vars -> Maybe Name
lastArgHead (Bind _ _ (Pi _ _ Explicit ty) sc@(Bind {})) = lastArgHead sc <|> retHead ty
lastArgHead (Bind _ _ (Pi _ _ Explicit ty) sc) = retHead ty
lastArgHead (Bind _ _ _ sc) = lastArgHead sc
lastArgHead _ = Nothing


||| The unsolved metavariables of a term
unsolvedMetas : Term vars -> List (Term vars)
unsolvedMetas tm@(Meta _ _ _ args) = tm :: concatMap unsolvedMetas args
unsolvedMetas (Bind _ _ b sc) = concatMap unsolvedMetas b
unsolvedMetas (App _ f a) = unsolvedMetas f ++ unsolvedMetas a
unsolvedMetas (As _ _ _ p) = unsolvedMetas p
unsolvedMetas (TDelayed _ _ t) = unsolvedMetas t
unsolvedMetas (TDelay _ _ _ a) = unsolvedMetas a
unsolvedMetas (TForce _ _ t) = unsolvedMetas t
unsolvedMetas _ = []

||| The type constructor at the head of a goal of a search, and its arguments
goalHead : Term vars -> Maybe (Name, List (Term vars))
goalHead tm
    = case getFnArgs tm of
           (Ref _ (TyCon _) n, args) => Just (n, args)
           _ => Nothing

||| Whether a type (after its Pi binders) is the type constructor `n` applied
||| to arguments
retHeadIs : Name -> Term vars -> Bool
retHeadIs n (Bind _ _ (Pi {}) sc) = retHeadIs n sc
retHeadIs n tm = map fst (goalHead tm) == Just n

isEmptyNotes : Doc IdrisAnn -> Bool
isEmptyNotes d = null (trim (show d))

||| The default hints (`%defaulthint`) for the type constructor at the head
||| of a goal, if there are any: a numeric literal of an unknown type is an
||| `Integer`, for example.
defaultsNote : {vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               {auto s : Ref Syn SyntaxInfo} ->
               {auto mnames : Ref MsgNames MsgNameState} ->
               Term vars -> Core (Doc IdrisAnn)
defaultsNote g
    = do let Just (n, _) = goalHead g
           | Nothing => pure emptyDoc
         defs <- get Ctxt
         ds <- for (map fst (filter snd (toList (autoHints defs)))) $ \ h =>
                 do Just gdef <- lookupCtxtExact h (gamma defs)
                      | Nothing => pure Nothing
                    if retHeadIs n (type gdef)
                       then pure (Just !(pshow Env.empty (type gdef)))
                       else pure Nothing
         case catMaybes ds of
              [] => pure emptyDoc
              ds => do tn <- prettyName n
                       pure $ reflow "The default for" <++> code (pretty0 tn) <+> comma
                                <++> concatWith (surround (comma <+> space)) (map code ds)
                                <+> comma <++> reflow "is only used when nothing else says what it is."
                                <+> line

||| Why a search found nothing for a goal, as far as can be told from the
||| hints in the context without searching again: the goal is not known
||| well enough to choose an implementation (it has unsolved metavariables
||| in determining positions), no implementation of the interface matches its
||| head, the only ones that do are not visible, or a local implementation
||| of the interface is in scope but for other arguments. Run only when a
||| search failure is printed.
searchNotes : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              {auto s : Ref Syn SyntaxInfo} ->
              {auto mnames : Ref MsgNames MsgNameState} ->
              (errfc : FC) -> Env Term vars -> Term vars -> Core (Doc IdrisAnn)
searchNotes errfc env g_in
    = catch (notes g_in) (\ _ => pure emptyDoc)
  where
    -- the local variables whose types are the type constructor `n` applied
    -- to arguments
    localsOf : {vs : _} -> Name -> Env Term vs -> Core (List (Doc IdrisAnn))
    localsOf n [] = pure []
    localsOf n (b :: env)
        = do rest <- localsOf n env
             if retHeadIs n (binderType b)
                then pure (code !(pshow env (binderType b)) :: rest)
                else pure rest

    commaList : List (Doc IdrisAnn) -> Doc IdrisAnn
    commaList [x] = x
    commaList [x, y] = x <++> "and" <++> y
    commaList xs = concatWith (surround (comma <+> space)) xs

    notes : Term vars -> Core (Doc IdrisAnn)
    notes g_in
        = do defs <- get Ctxt
             g <- normaliseHoles defs env g_in
             let Just (n, args) = goalHead g
               | Nothing => pure emptyDoc
             syn <- get Syn
             let isIface = isJust (lookupExact n (ifaces syn))
             tn <- prettyName n
             -- The arguments that choose an implementation
             dets <- the (Core (Maybe NatSet))
                       (catch (Just . detArgs <$> getSearchData errfc False n)
                              (\ _ => pure Nothing))
             let chosen : List (Term vars)
                 chosen = case dets of
                            Just ds => if NatSet.isEmpty ds then args
                                          else NatSet.take ds args
                            Nothing => args
             -- The hints that can match the goal, whatever its
             -- metavariables stand for
             -- (the names of the hints' types are resolved, and the error's
             -- are full names)
             nfg <- nf defs env !(toResolvedNames g)
             th <- targetHeads nfg
             -- (only the direct hints: the others, such as the hints that
             -- give the implementation of a parent interface, match anything)
             let hints = maybe [] (map fst . filter snd) (lookup n (typeHints defs))
             found <- for hints $ \ h =>
                        do Just gdef <- lookupCtxtExact h (gamma defs)
                             | Nothing => pure Nothing
                           if maybe True (\ th => hintCanMatch th (type gdef)) th
                              then pure (Just gdef)
                              else pure Nothing
             let nss = currentNS defs :: nestedNS defs
             let visible : GlobalDef -> Bool
                 visible gdef = visibleInAny nss (fullname gdef)
                                             (collapseDefault $ visibility gdef)
             let matching = catMaybes found
             locals <- localsOf n env
             let localNote
                   = case locals of
                       [] => emptyDoc
                       _ => commaList locals <++> reflow (if length locals == 1
                                                             then "is in scope, but does not match."
                                                             else "are in scope, but do not match.")
                              <+> line
             gdoc <- pshow env g
             what <- case args of
                       [] => pure (code (pretty0 tn))
                       [a] => do ad <- argDoc a
                                 pure (code (pretty0 tn) <++> "for" <++> code ad)
                       _ => pure (code gdoc)
             let none = if isIface
                           then reflow "There is no implementation of" <++> what
                                  <++> reflow "in scope." <+> line
                           else emptyDoc
             -- A variable of the type of the definition can only have an
             -- implementation from a constraint
             let typeVars = filter isLocal chosen
             case (filter visible matching, filter (not . visible) matching) of
               ([], []) => pure $ none <+> localNote <+> constraintHint (isIface && not (null typeVars)) gdoc
               ([], hidden@(_ :: _)) =>
                  do ds <- traverse (\ gdef => candidateDesc errfc (fullname gdef) False) hidden
                     pure $ vsep (map (<++> reflow "matches, but is not visible here.") ds)
                              <+> line <+> localNote
               _ => case (concatMap unsolvedMetas chosen, typeVars) of
                      ((m :: _), _) =>
                         do md <- pshowNoNorm env m
                            let mname = trim (fst (break (== '[') (show md)))
                            dflt <- defaultsNote g
                            pure $ code (pretty0 mname) <++> reflow "is not known, so I can't choose"
                                     <++> (if isIface then reflow "an implementation of" else reflow "a value of")
                                     <++> code (pretty0 tn) <+> dot <+> line <+> dflt
                                     <+> reflow "Suggestion: say what" <++> code (pretty0 mname)
                                     <++> reflow "is, with a type annotation such as"
                                     <++> code "the T e" <+> dot <+> line
                      ([], (_ :: _)) =>
                         pure $ none <+> localNote <+> constraintHint isIface gdoc
                      _ => case mapMaybe stuckFn chosen of
                             ((a, fn) :: _) =>
                               do ad <- pshow env a
                                  gdef <- lookupCtxtExact fn (gamma defs)
                                  let hidden = maybe False (\ gd => not (reducibleInAny nss (fullname gd)
                                                                           (collapseDefault $ visibility gd))) gdef
                                  pure $ code ad <++> reflow "does not reduce here, so I can't tell which type it is"
                                           <+> (if hidden then reflow ": its definition is not" <++> code "public export"
                                                   else emptyDoc)
                                           <+> dot <+> line <+> localNote
                             [] => pure localNote
    where
      isLocal : Term vars -> Bool
      isLocal (Local {}) = True
      isLocal _ = False

      hasVars : Term vs -> Bool
      hasVars (Local {}) = True
      hasVars (Meta {}) = True
      hasVars (App _ f a) = hasVars f || hasVars a
      hasVars (Bind {}) = True
      hasVars _ = False

      -- An application of a function to values without variables that did
      -- not reduce (when the definition is not visible here, for example)
      stuckFn : Term vars -> Maybe (Term vars, Name)
      stuckFn a = case getFnArgs a of
                       (Ref _ Func fn, args) => if any hasVars args then Nothing else Just (a, fn)
                       _ => Nothing

      -- (a metavariable on its own is printed without the variables in
      -- scope)
      argDoc : Term vars -> Core (Doc IdrisAnn)
      argDoc a@(Meta {}) = do d <- pshowNoNorm env a
                              pure (pretty0 (trim (fst (break (== '[') (show d)))))
      argDoc a = pshow env a

      -- A type variable can only be given an implementation by a
      -- constraint of the definition
      constraintHint : Bool -> Doc IdrisAnn -> Doc IdrisAnn
      constraintHint False _ = emptyDoc
      constraintHint True g
          = reflow "Suggestion: add the constraint" <++> code g
              <++> reflow "to the type of the definition." <+> line

||| The candidates of a chain of needed sub-goals, each with its sub-goal,
||| and why the last sub-goal failed
chainLevels : {auto c : Ref Ctxt Defs} ->
              {auto s : Ref Syn SyntaxInfo} ->
              {auto o : Ref ROpts REPLOpts} ->
              {auto mnames : Ref MsgNames MsgNameState} ->
              (errfc : FC) -> Error -> Core (List ChainLevel, Doc IdrisAnn)
chainLevels errfc (SearchNeeds _ sgam cand isLocal senv sg cause)
    = do defs <- get Ctxt
         setCtxt sgam
         let (_ ** (senv', sg')) = dropEnv senv sg
         k <- kind cand isLocal
         sdesc <- pshow senv' sg'
         (rest, final) <- the (Core (List ChainLevel, Doc IdrisAnn)) $ case cause of
                            Just r@(SearchNeeds {}) => do put Ctxt defs
                                                          chainLevels errfc r
                            Just r => do d <- perrorRaw r
                                         pure ([], reflow "Possible cause:" <++> d)
                            Nothing => pure ([], !(searchNotes errfc senv' sg'))
         put Ctxt defs
         pure (MkLevel k sdesc :: rest, final)
  where
    kind : Name -> Bool -> Core CandidateKind
    kind n True = pure (LocalCand (code (pretty0 (nameRoot n))))
    kind n False
        = do defs <- get Ctxt
             Just gdef <- lookupCtxtExact n (gamma defs)
               | Nothing => pure (HintCand (code (pretty0 n)))
             let ty = type gdef
             let loc = defLoc errfc (location gdef)
             isPairCon <- case (definition gdef, retHead ty) of
                            (DCon {}, Just tn) => isPairType tn
                            _ => pure False
             syn <- get Syn
             let isIfaceTy = maybe False (\ tn => isJust (lookupExact tn (ifaces syn))) (retHead ty)
             tyd <- pshow Env.empty ty
             nm <- prettyName (fullname gdef)
             let named = code (pretty0 nm <++> colon <++> tyd) <++> parens loc
             if isPairCon then pure PairCon
               else if isParentHint (fullname gdef)
                 then do p <- traverseOpt (\ n => prettyName !(toFullNames n)) (retHead ty)
                         c <- traverseOpt (\ n => prettyName !(toFullNames n)) (lastArgHead ty)
                         pure (ParentOf (pretty0 (fromMaybe "" p)) (pretty0 (fromMaybe "" c)))
               else if isUnnamedImpl (fullname gdef)
                 then pure (ImplCand (code tyd <++> parens loc))
               else case definition gdef of
                      DCon {} => pure (ConCand named)
                      _ => pure (if isIfaceTy then ImplCand named else HintCand named)
chainLevels errfc err = pure ([], !(perrorRaw err))

perrorRaw (Fatal err) = perrorRaw err
perrorRaw err@(CantConvert fc _ _ _ _)
    = do Just (hd, _) <- pairHeadline err
           | Nothing => pure emptyDoc
         pure $ hd <+> line <+> !(ploc fc)
perrorRaw err@(CantSolveEq fc _ _ _ _ others)
    = do Just (hd, _) <- pairHeadline err
           | Nothing => pure emptyDoc
         ds <- traverse other (take maxOthers others)
         let more = length others `minus` maxOthers
         pure $ hd <+> line <+> !(ploc fc)
           <+> (case catMaybes ds of
                     [] => emptyDoc
                     ds => line <+> reflow "Also left unsolved" <+> colon <+> line
                             <+> indent 4 (vsep (ds ++ (if more == 0 then []
                                    else [reflow ("... and " ++ show more ++ " more")])))
                             <+> line)
  where
    maxOthers : Nat
    maxOthers = 5

    other : Error -> Core (Maybe (Doc IdrisAnn))
    other (CantSolveEq ofc gam env l r _)
        = do (_, (ld, rd)) <- pairLine "" gam env l r
             pure $ Just $ code ld <++> "and" <++> code rd
                      <+> maybe emptyDoc (const (space <+> parens ("at" <++> annotate FileCtxt (pretty0 ofc))))
                                (isNonEmptyFC ofc)
    other _ = pure Nothing
perrorRaw (PatternVariableUnifies fc fct env n tm)
    = do let (min, max) = order fc fct
         pure $ errorDesc (hsep [ reflow "Pattern variable"
                  , code (prettyVar n)
                  , reflow "unifies with" <+> colon
                  , code !(pshow env tm) <+> dot
                  ]) <+> line <+> !(ploc2 min max) <+> line
                     <+> reflow "Suggestion: Use the same name for both pattern variables, since they unify."
  where
    prettyVar : Name -> Doc IdrisAnn
    prettyVar (PV n _) = prettyVar n
    prettyVar n = pretty0 n
    order : FC -> FC -> (FC, FC)
    order fc1 fc2 =
      let Just (_, sr1, sc1) = isNonEmptyFC fc1
           | Nothing => (EmptyFC, fc2)
          Just (_, sr2, sc2) = isNonEmptyFC fc2
           | Nothing => (fc1, EmptyFC)
      in if sr1 < sr2 then (fc1, fc2) else if sr1 == sr2 && sc1 < sc2 then (fc1, fc2) else (fc2, fc1)
perrorRaw (CyclicMeta fc env n tm)
    = pure $ errorDesc (reflow "Cycle detected in solution of metavariable"
        <++> meta (pretty0 !(prettyName n)) <++> equals
        <++> code !(pshow env tm)) <+> line <+> !(ploc fc)
perrorRaw (WhenUnifying _ Unordered gam env x y inferred err)
    = do defs <- get Ctxt
         setCtxt gam
         let res = errorDesc (reflow "When unifying:" <+> line
                   <+> "    " <+> code !(pshow env x) <+> line <+> "and:" <+> line
                   <+> "    " <+> code !(pshow env y)) <+> line <+> !(perrorRaw err)
         note <- inferredNote env inferred
         put Ctxt defs
         pure (res <+> note)
perrorRaw (WhenUnifying _ GotExpected gam env x y inferred err)
    = do defs <- get Ctxt
         setCtxt gam
         got <- pshow env x
         exp <- pshow env y
         note <- inferredNote env inferred
         put Ctxt defs
         let labelled = errorDesc (reflow "When unifying:" <+> line
                          <+> expectedGot exp got)
         -- When the inner error is about the same two terms, in the same
         -- order, say it first and print the two terms once more, labelled,
         -- rather than printing the same pair twice without labels.
         Just (hd, (l, r)) <- pairHeadline err
           | Nothing => pure $ labelled <+> line <+> !(perrorRaw err) <+> note
         let fc = fromMaybe emptyFC (getErrorLoc err)
         if show l == show got && show r == show exp
            then pure $ hd <+> line <+> labelled <+> line <+> !(ploc fc) <+> note
            else pure $ labelled <+> line <+> hd <+> line <+> !(ploc fc) <+> note
perrorRaw (ValidCase fc env (Left tm))
    = pure $ errorDesc (code !(pshow env tm) <++> reflow "is not a valid impossible case.")
        <+> line <+> !(ploc fc)
perrorRaw (ValidCase _ env (Right err))
    = pure $ errorDesc (reflow "Impossible pattern gives an error" <+> colon) <+> line <+> !(perrorRaw err)
perrorRaw (UndefinedName fc x)
    = pure $ errorDesc (reflow "Undefined name" <++> code (pretty0 x) <+> dot) <+> line <+> !(ploc fc)
        <+> !(importHint x)
perrorRaw (InvisibleName fc n (Just ns))
    = pure $ errorDesc ("Name" <++> code (pretty0 n) <++> reflow "is inaccessible since"
        <++> code (pretty0 ns) <++> reflow "is not explicitly imported.")
        <+> line <+> !(ploc fc)
        <+> line <+> reflow "Suggestion: add an explicit" <++> keyword "export" <++> "or" <++> keyword ("public" <++> "export")
        <++> reflow "modifier. By default, all names are" <++> keyword "private" <++> reflow "in namespace blocks."
perrorRaw (InvisibleName fc x Nothing)
    = pure $ errorDesc ("Name" <++> code (pretty0 x) <++> reflow "is private.") <+> line <+> !(ploc fc)
        <+> line <+> reflow "Suggestion: add an explicit" <++> keyword "export" <++> "or" <++> keyword ("public" <++> "export")
        <++> reflow "modifier. By default, all names are" <++> keyword "private" <++> reflow "in namespace blocks."
perrorRaw (BadTypeConType fc n)
    = pure $ errorDesc (reflow "Return type of" <++> code (pretty0 n) <++> reflow "must be" <++> code "Type"
        <+> dot) <+> line <+> !(ploc fc)
perrorRaw (BadDataConType fc n fam)
    = pure $ errorDesc (reflow "Return type of" <++> code (pretty0 n) <++> reflow "must be in"
        <++> code (pretty0 fam)) <++> line <+> !(ploc fc)
perrorRaw (NotCovering fc n IsCovering)
    = pure $ errorDesc (reflow "Internal error" <++> parens (reflow "Coverage of" <++> code (pretty0 n)))
perrorRaw (NotCovering fc n (MissingCases cs))
    = pure $ errorDesc (code (pretty0 !(prettyName n)) <++> reflow "is not covering.")
        <+> line <+> !(ploc fc) <+> line
        <+> reflow "Missing cases" <+> colon <+> line
        <+> indent 4 (vsep (!(traverse pshowPattern (take maxMissing cs))
                            ++ more (length cs `minus` maxMissing))) <+> line
  where
    maxMissing : Nat
    maxMissing = 10

    more : Nat -> List (Doc IdrisAnn)
    more Z = []
    more k = [reflow ("... and " ++ show k ++ " more")]
perrorRaw (NotCovering fc n (NonCoveringCall ns))
    = pure $ errorDesc (!(headlineName n ns) <++> reflow "is not covering.")
        <+> line <+> !(ploc (firstCallTo fc !(callsTo n ns))) <+> line
        <+> reflow "Calls non covering function" <+>
        (case !(traverse calledName ns) of
             [fn] => space <+> fn
             ds => pretty0 's' <+> colon <++> concatWith (surround (comma <+> space)) ds)
        <+> !(implCoverageNotes ns)
  where
    -- The machine name of a case or with block says nothing to the user
    -- ("Main.case block in case block in main"): say where it is instead
    outerName : String -> String
    outerName s
        = if "case block in " `isPrefixOf` s then outerName (assert_smaller s (substr 14 (length s) s))
          else if "with block in " `isPrefixOf` s then outerName (assert_smaller s (substr 14 (length s) s))
          else s

    blockOf : Name -> Maybe (String, String)
    blockOf (NS _ n) = blockOf n
    blockOf (CaseBlock outer _) = Just ("a case block in", outerName outer)
    blockOf (WithBlock outer _) = Just ("a with block in", outerName outer)
    blockOf _ = Nothing

    calledName : Name -> Core (Doc IdrisAnn)
    calledName cn
        = case blockOf cn of
            Nothing => defName cn
            Just (what, outer) =>
              do defs <- get Ctxt
                 loc <- maybe emptyDoc (\ gdef => case isNonEmptyFC (location gdef) of
                                                     Just _ => space <+> parens ("at" <++> annotate FileCtxt (pretty0 (location gdef)))
                                                     Nothing => emptyDoc)
                          <$> lookupCtxtExact cn (gamma defs)
                 pure (reflow what <++> code (pretty0 outer) <+> loc)
perrorRaw (NotTotal fc n r_in)
    = do let r = onceRound r_in
         let headline = errorDesc (code !(headlineName n (reasonNames r))
                          <++> reflow "is not total," <++> pretty0 r)
         (efc, details) <- explain r
         pure $ headline <+> line <+> !(ploc efc) <+> details
  where
    reasonNames : PartialReason -> List Name
    reasonNames (BadCall ns) = ns
    reasonNames (BadPath init n) = n :: map snd init
    reasonNames (RecPath loop) = map snd loop
    reasonNames _ = []

    displayName : Name -> Core (Doc IdrisAnn)
    displayName = defName

    -- Say where each call on the problematic path happens, so that it's
    -- clear which call needs fixing
    callSite : (FC, Name) -> Core (Maybe (Doc IdrisAnn))
    callSite (cfc, cn)
        = case isNonEmptyFC cfc of
               Nothing => pure Nothing
               Just _ => pure $ Just $
                   code !(displayName cn) <++> reflow "called at"
                   <++> annotate FileCtxt (pretty0 cfc)

    callSites : String -> List (FC, Name) -> Core (Doc IdrisAnn)
    callSites hdr cs
        = case catMaybes !(traverse callSite cs) of
               [] => pure emptyDoc
               ds => pure $ line <+> reflow hdr <+> colon <+> line
                       <+> indent 4 (vsep ds) <+> line

    firstCall : List (FC, Name) -> FC
    firstCall = firstCallTo fc

    -- Why a function called on the path is not total, in one line
    whyNot : Name -> Core (Doc IdrisAnn)
    whyNot g
        = do defs <- get Ctxt
             Just gdef <- lookupCtxtExact g (gamma defs)
               | Nothing => pure emptyDoc
             let NotTerminating gr = isTerminating (totality gdef)
               | _ => pure emptyDoc
             gr <- onceRound <$> toFullNames gr
             pure $ line <+> code !(displayName g) <++> reflow "is not total,"
                      <++> pretty0 gr <+> dot <+> line

    -- The names of the arguments of `n`, in order, and whether each is
    -- explicit
    argNames : Core (List (Maybe Name, Bool))
    argNames
        = do defs <- get Ctxt
             Just gdef <- lookupCtxtExact n (gamma defs)
               | Nothing => pure []
             pure (binders (type gdef))
      where
        binders : Term vs -> List (Maybe Name, Bool)
        binders (Bind _ x (Pi _ _ info _) sc)
            = (userName x, isExplicit info) :: binders sc
          where
            userName : Name -> Maybe Name
            userName x@(UN (Basic _)) = Just x
            userName _ = Nothing

            isExplicit : PiInfo t -> Bool
            isExplicit Explicit = True
            isExplicit _ = False
        binders _ = []

    -- A pattern something could be smaller than: one matching a constructor
    -- or a literal
    matching : Term vs -> Bool
    matching (As _ _ _ p) = matching p
    matching (PrimVal {}) = True
    matching tm
        = case getFn tm of
               Ref _ (DataCon {}) _ => True
               Ref _ (TyCon {}) _ => True
               _ => False

    -- How each argument of a call to `n` from `n` itself compares to the
    -- pattern in the same position
    selfCallArgs : FC -> Core (Maybe (Doc IdrisAnn))
    selfCallArgs cfc
        = do Just (MkCallArgs env pats args changes) <- callArgsAt n cfc n
               | Nothing => pure Nothing
             names <- argNames
             let positions = number 1 (zip names (zip pats args))
             let rows = zipWith (\ i, row => fromMaybe Unknown (getAt i row))
                                [0 .. length changes] changes
             let cands = filter (\ (_, (_, (p, _)), _) => matching p)
                                (zipWith (\ (i, x), c => (i, x, c)) positions rows)
             case cands of
               [] => pure $ Just $ line <+> (if null pats
                       then reflow "The recursive call has no arguments that could get smaller."
                       else reflow "No argument gets smaller: none is matched against a constructor.")
                       <+> line
               _ => do ds <- traverse (argLine env) (take 3 cands)
                       let more = length cands `minus` 3
                       pure $ Just $ line <+> vsep ds
                         <+> (if more == 0 then emptyDoc
                                 else line <+> reflow ("... and " ++ show more ++ " more"))
                         <+> line
      where
        number : Nat -> List ((Maybe Name, Bool), a) -> List (Maybe Nat, Maybe Name, a)
        number i [] = []
        number i (((x, True), v) :: rest) = (Just i, x, v) :: number (S i) rest
        number i (((x, False), v) :: rest) = (Nothing, x, v) :: number i rest

        -- The laziness is implicit in the source
        unlazy : Term vs -> Term vs
        unlazy (TForce _ _ t) = unlazy t
        unlazy (TDelay _ _ _ t) = unlazy t
        unlazy (App fc f a) = App fc (unlazy f) (unlazy a)
        unlazy t = t

        argDesc : Maybe Nat -> Maybe Name -> Doc IdrisAnn
        argDesc (Just i) x = "Argument" <++> byShow i
                               <+> maybe emptyDoc (\ x => space <+> parens (code (pretty0 x))) x
        argDesc Nothing (Just x) = reflow "Implicit argument" <++> code (pretty0 x)
        argDesc Nothing Nothing = reflow "An implicit argument"

        argLine : {vs : _} -> Env Term vs ->
                  (Maybe Nat, (Maybe Name, (Term vs, Term vs)), SizeChange) ->
                  Core (Doc IdrisAnn)
        argLine env (i, (x, (p, a)), c)
            = do pd <- pshow env (unlazy p)
                 ad <- pshow env (unlazy a)
                 pure $ argDesc i x <+> colon <++> "passed" <++> code ad
                          <+> comma <++> reflow (case c of
                                                    Same => "which is not smaller than the pattern"
                                                    _ => "which is not known to be smaller than the pattern")
                          <++> code pd <+> dot

    explain : PartialReason -> Core (FC, Doc IdrisAnn)
    explain (RecPath loop@((cfc, g) :: rest))
        = if all (\ (cfc', g') => cfc' == cfc && g' == g) rest && g == n
             then do Just d <- selfCallArgs cfc
                       | Nothing => pure (firstCall loop, !(callSites "Calls on the recursive path" loop))
                     pure (firstCall loop, d)
             else pure (firstCall loop, !(callSites "Calls on the recursive path" loop))
    explain (BadPath init g)
        = do path <- case init of
                          [_] => pure emptyDoc
                          _ => callSites "Calls leading to the non-terminating function" init
             pure (firstCall init, path <+> !(whyNot g))
    explain (BadCall ns)
        = do defs <- get Ctxt
             sites <- callsTo n ns
             -- why the function called first is not total
             case sites ++ map (EmptyFC,) ns of
                  ((_, g) :: _) => pure (firstCall sites, !(whyNot g))
                  [] => pure (fc, emptyDoc)
    explain _ = pure (fc, emptyDoc)
perrorRaw ImpossibleCase
    = pure $ errorDesc (reflow "<ImpossibleCase: this should never be displayed>")
perrorRaw (LinearUsed fc count n)
    = pure $ errorDesc (reflow "There are" <++> byShow count <++> reflow "uses of linear name"
        <++> code (pretty0 (sugarName n)) <+> dot)
        <++> line <+> !(ploc fc)
        <+> line <+> reflow "Suggestion: linearly bounded variables must be used exactly once."
perrorRaw (LinearMisuse fc n exp ctx)
    = if isErased exp
         then pure $ errorDesc (code (pretty0 n) <++> reflow "is not accessible in this context.")
                <+> line <+> !(ploc fc)
         else pure $ errorDesc (reflow "Trying to use" <++> prettyRig exp <++> "name"
                <++> code (pretty0 (sugarName n)) <++> "in" <++> prettyRel ctx <++> "context.")
                <+> line <+> !(ploc fc)
  where
    -- quantity variables with their owners if two of the same name meet
    vars : RigCount -> Maybe String
    vars r = if clashingVars exp ctx then showVarsCountOwned r else showVarsCount r

    prettyRig : RigCount -> Doc ann
    prettyRig = elimSemi "irrelevant"
                         "linear"
                         (\r => maybe "unrestricted" pretty0 (vars r))

    prettyRel : RigCount -> Doc ann
    prettyRel = elimSemi "irrelevant"
                         "relevant"
                         (\r => maybe "non-linear" pretty0 (vars r))
perrorRaw (BorrowPartial fc env tm arg)
    = pure $ errorDesc (code !(pshow env tm) <++> reflow "borrows argument" <++> code !(pshow env arg)
        <++> reflow "so must be fully applied.")
        <+> line <+> !(ploc fc)
perrorRaw (BorrowPartialType fc env tm)
    = pure $ errorDesc (code !(pshow env tm) <++>
        reflow "borrows, so must return a concrete type.") <+> line <+> !(ploc fc)
perrorRaw (AmbiguousName fc ns)
    = pure $ errorDesc (reflow "Ambiguous name" <++> code (pretty0 (nameRoot (fromMaybe (UN Underscore) (head' ns))))
        <+> comma <++> reflow "which could be" <++> alternatives (map pretty0 ns) <+> dot)
        <+> line <+> !(ploc fc)
  where
    alternatives : List (Doc IdrisAnn) -> Doc IdrisAnn
    alternatives [x, y] = code x <++> "or" <++> code y
    alternatives xs = reflow "any of" <+> colon <++> concatWith (surround (comma <+> space)) (map code xs)
perrorRaw (AmbiguousElab fc env ts_in)
    = do pp <- getPPrint
         setPPrint ({ fullNamespace := True } pp)
         -- each result is checked in its own context, so its names are
         -- not compared with those of the others
         ts_show <- traverse (\ (gam, t) =>
                                  do defs <- get Ctxt
                                     setCtxt gam
                                     res <- distinctNames (pshow env t)
                                     put Ctxt defs
                                     pure res) ts_in
         let res = vsep [ errorDesc (reflow "Ambiguous elaboration. Possible results" <+> colon)
                        , indent 4 (vsep ts_show)
                        ] <+> line <+> !(ploc fc)
         setPPrint pp
         pure res
perrorRaw (AmbiguousSearch {vars} fc env tgt ts)
    = do descs <- traverse result ts
         -- results built from the same hint are told apart by the rest
         let shown = map (show . fst) descs
         descs' <- traverse (\ (d, t) =>
                               if count (== show d) shown > 1
                                  then pure (d <+> comma <++> "as" <++> code !(pshowNoNorm env t))
                                  else pure d) (zip (map fst descs) ts)
         let named = mapMaybe snd descs
         let unnamed = length (filter isUnnamed ts)
         pure $ vsep [ errorDesc (reflow "Multiple solutions found in search of" <+> colon)
                     , indent 4 !(pshowNoNorm env tgt)
                     , !(ploc fc)
                     , reflow "Possible correct results" <+> colon
                     , indent 4 (vsep descs')
                     ] <+> suggestion named unnamed
  where
    isUnnamed : Term vars -> Bool
    isUnnamed t = case getFnArgs t of
                       (Ref _ _ n, _) => isUnnamedImpl n
                       _ => False

    -- A result built from a global hint is shown as the hint, with its
    -- name if it has one; any other as the term found
    result : Term vars -> Core (Doc IdrisAnn, Maybe String)
    result t
        = do defs <- get Ctxt
             let (Ref _ _ n, _) = getFnArgs t
               | _ => pure (!(pshowNoNorm env t), Nothing)
             Just gdef <- lookupCtxtExact n (gamma defs)
               | Nothing => pure (!(pshowNoNorm env t), Nothing)
             d <- hintDesc fc gdef
             if isUnnamedImpl (fullname gdef)
                then pure (d, Nothing)
                else pure (d, Just !(prettyName (fullname gdef)))

    suggestion : List String -> Nat -> Doc IdrisAnn
    suggestion [] Z = emptyDoc
    suggestion [] _
        = line <+> reflow "Suggestion: remove one of the implementations, or give them names ("
            <+> code "[name] Interface t where" <+> reflow ") to choose one with"
            <++> code "@{name}" <+> dot
    suggestion ns _
        = line <+> reflow "Suggestion: choose one with"
            <++> concatWith (surround (space <+> "or" <+> space))
                   (map (\ n => code ("@{" <+> pretty0 n <+> "}")) (nub ns))
            <+> dot

perrorRaw (AmbiguityTooDeep fc n ns)
    = pure $ errorDesc (reflow "Maximum ambiguity depth exceeded in" <++> code (pretty0 !(getFullName n))
        <+> colon) <+> line <+> concatWith (surround " --> ") (pretty0 <$> !(traverse getFullName ns))
        <++> line <+> !(ploc fc)
        <+> line <+> reflow "Suggestion: the default ambiguity depth limit is 3, the" <++> code "%ambiguity_depth"
        <++> reflow "pragma can be used to extend this limit, but beware compilation times can be severely impacted."
perrorRaw (AllFailed _ ts)
    = case allUndefined ts of
           Just e => perrorRaw e
           _ => do count <- candidateErrorCount <$> getSession
                   let (shown, hidden) = if count == 0 then (ts, Prelude.Nil) else splitAt count ts
                   keyed <- traverse (\ t => pure (groupKey (snd t), t)) shown
                   groups <- traverse pGroup (groupBy keyed)
                   pure $ errorDesc (reflow "Sorry, I can't find any elaboration which works. All errors" <+> colon) <+> line
                     <+> vsep groups
                     <+> more (length hidden)
  where
    pCandidate : Maybe Name -> Doc IdrisAnn -> Core (Doc IdrisAnn)
    pCandidate (Just n) doc
       = pure $ "If" <++> code (pretty0 !(aliasName !(getFullName n))) <+> colon <++> doc
    pCandidate Nothing doc
       = pure $ reflow "Possible error" <+> colon <+> line <+> indent 4 doc

    pAlterror : (Maybe Name, Error) -> Core (Doc IdrisAnn)
    pAlterror (mn, err) = pCandidate mn !(distinctNames (perrorRaw err))

    -- The error that says what went wrong, under the context it was found in
    innermost : Error -> Error
    innermost (WhenUnifying _ _ _ _ _ _ _ err) = innermost err
    innermost (Fatal err) = innermost err
    innermost err = err

    -- Candidates whose errors are of the same kind, at the same place, share
    -- one source excerpt
    groupKey : Error -> Maybe (FC, Nat)
    groupKey err
        = do kind <- case innermost err of
                          CantConvert {} => Just 0
                          CantSolveEq {} => Just 1
                          _ => Nothing
             fc <- getErrorLoc (innermost err)
             _ <- isNonEmptyFC fc
             pure (fc, kind)

    -- Group by key, in the order of the first member of each group
    groupBy : List (Maybe (FC, Nat), a) -> List (Maybe (FC, Nat), List1 a)
    groupBy [] = []
    groupBy ((Nothing, x) :: xs) = (Nothing, singleton x) :: groupBy xs
    groupBy ((Just k, x) :: xs)
        = let (same, rest) = partition (\ y => fst y == Just k) xs in
              (Just k, x ::: map snd same) :: groupBy (assert_smaller xs rest)

    -- For a mismatch between the type of an expression and the type
    -- expected of it, the type of the expression
    gotType : Error -> Core (Maybe String)
    gotType (WhenUnifying _ GotExpected gam env x _ _ _)
        = do defs <- get Ctxt
             setCtxt gam
             d <- pshow env x
             put Ctxt defs
             pure (Just (show d))
    gotType _ = pure Nothing

    -- One line for a candidate whose source excerpt is shown with others:
    -- the error without its excerpt, and without the labelled pair of types
    -- when that pair repeats the inner error
    pShort : Error -> Core (Doc IdrisAnn)
    pShort err@(WhenUnifying _ GotExpected gam env x y _ inner)
        = do defs <- get Ctxt
             setCtxt gam
             got <- pshow env x
             exp <- pshow env y
             put Ctxt defs
             Just (hd, (l, r)) <- pairHeadline inner
               | Nothing => perrorRaw (killErrorLoc err)
             if show l == show got && show r == show exp
                then pure hd
                else perrorRaw (killErrorLoc err)
    pShort err = perrorRaw (killErrorLoc err)

    sameRoot : List (Maybe Name) -> Maybe String
    sameRoot (Just n :: ns)
        = if all (\ m => map nameRoot m == Just (nameRoot n)) ns
             then Just (nameRoot n) else Nothing
    sameRoot _ = Nothing

    pGroup : (Maybe (FC, Nat), List1 (Maybe Name, Error)) -> Core (Doc IdrisAnn)
    pGroup (Just (fc, _), grp@(_ ::: _ :: _))
        = do gots <- traverse (distinctNames . gotType . snd) (forget grp)
             lines <- traverse (\ (mn, err) => pCandidate mn !(distinctNames (pShort err))) (forget grp)
             let n = length grp
             let summary
                   = case gots of
                          (Just g :: gs) =>
                             if all (== Just g) gs
                                then Just $ reflow (if n == length ts then "All" else "These")
                                       <++> byShow n <++> "candidates"
                                       <+> maybe emptyDoc (\ r => space <+> "for" <++> code (pretty0 r))
                                                 (sameRoot (map fst (forget grp)))
                                       <++> reflow "fail on the same expression, of type"
                                       <++> code (pretty0 g) <+> colon
                                else Nothing
                          _ => Nothing
             pure $ maybe (vsep lines) (\ s => vsep [s, indent 4 (vsep lines)]) summary
                    <+> line <+> !(ploc fc)
    pGroup (_, grp) = vsep <$> traverse pAlterror (forget grp)

    more : Nat -> Doc IdrisAnn
    more Z = emptyDoc
    more k = line <+> reflow ("... and " ++ show k ++ " more candidate" ++ (if k == 1 then "" else "s")
                          ++ ". Use") <++> code "--candidate-error-count 0"
                          <++> reflow "to see them all."

    allUndefined : List (Maybe Name, Error) -> Maybe Error
    allUndefined [] = Nothing
    allUndefined [(_, err@(UndefinedName {}))] = Just err
    allUndefined ((_, err@(UndefinedName {})) :: es) = allUndefined es
    allUndefined _ = Nothing
perrorRaw (RecordTypeNeeded fc _)
    = pure $ errorDesc (reflow "Can't infer type for this record update.") <+> line <+> !(ploc fc)
perrorRaw (DuplicatedRecordUpdatePath fc ps)
    = pure $ vcat $
      errorDesc (reflow "Duplicated record update paths:")
      :: map (indent 2 . reAnnotate Syntax . prettyFieldPath) ps
      ++ [line <+> !(ploc fc)]
perrorRaw (NotRecordField fc fld Nothing)
    = pure $ errorDesc (code (pretty0 fld) <++> reflow "is not part of a record type.") <+> line <+> !(ploc fc)
perrorRaw (NotRecordField fc fld (Just ty))
    = pure $ errorDesc (reflow "Record type" <++> code (pretty0 !(getFullName ty)) <++> reflow "has no field"
        <++> code (pretty0 fld) <+> dot) <+> line <+> !(ploc fc)
perrorRaw (NotRecordType fc ty)
    = pure $ errorDesc (code (pretty0 !(getFullName ty)) <++> reflow "is not a record type.") <+> line <+> !(ploc fc)
perrorRaw (IncompatibleFieldUpdate fc flds)
    = pure $ reflow "Field update" <++> reAnnotate Syntax (prettyFieldPath flds)
             <++> reflow "not compatible with other updates at" <+> colon <+> line <+> !(ploc fc)
perrorRaw (InvalidArgs fc env [n] tm)
    = pure $ errorDesc (code (pretty0 n) <++> reflow "is not a valid argument in" <++> !(pshow env tm)
        <+> dot) <+> line <+> !(ploc fc)
perrorRaw (InvalidArgs fc env ns tm)
    = pure $ errorDesc (concatWith (surround (comma <+> space)) (code . pretty0 <$> ns)
        <++> reflow "are not valid arguments in" <++> !(pshow env tm) <+> dot)
        <+> line <+> !(ploc fc)
perrorRaw (TryWithImplicits fc env imps)
    = pure $ errorDesc (reflow "Need to bind implicits"
        <++> concatWith (surround (comma <+> space)) !(traverse (tshow env) imps) <+> dot)
        <+> line <+> !(ploc fc)
  where
    tshow : {vars : _} ->
            Env Term vars -> (Name, Term vars) -> Core (Doc IdrisAnn)
    tshow env (n, ty) = pure $ pretty0 n <++> colon <++> code !(pshow env ty)
perrorRaw (BadUnboundImplicit fc env n ty)
    = pure $ errorDesc (reflow "Can't bind name" <++> code (pretty0 (nameRoot n))
        <++> reflow "with type" <++> code !(pshow env ty)
        <+> colon) <+> line <+> !(ploc fc) <+> line <+> reflow "Suggestion: try an explicit bind."
perrorRaw (CantSolveGoal fc gam env g reason)
    = do defs <- get Ctxt
         setCtxt gam
         let (_ ** (env', g')) = dropEnv env g
         let res = errorDesc (reflow "Can't find an implementation for" <++> code !(pshow env' g')
                     <+> dot) <+> line <+> !(ploc fc)
         details <- case reason of
              -- Nothing matched: say why, as far as can be told
              Nothing => searchNotes fc env' g'
              -- A candidate matched, but one of its arguments (typically
              -- an interface constraint) couldn't be found
              Just r@(SearchNeeds {}) =>
                do (lvls, final) <- chainLevels fc r
                   let levels = mergePairs lvls
                   -- a parent interface is tried when nothing else
                   -- matched: say that first
                   first <- if startsWithParent levels
                               then searchNotes fc env' g'
                               else pure emptyDoc
                   if null levels
                      then pure final
                      else pure (first <+> pChain 0 (length levels) levels final
                                   <+> (if isEmptyNotes final then line else emptyDoc))
              Just r => do rdesc <- perrorRaw r
                           pure (reflow "Possible cause:" <++> rdesc)
         put Ctxt defs
         pure (if isEmptyNotes details then res else res <+> line <+> details)
  where
    -- One line for each candidate of a chain that matched and needed a
    -- sub-goal that failed, indented under the one before; at most 4, the
    -- first three and the last
    pChain : (level : Nat) -> (count : Nat) -> List ChainLevel -> Doc IdrisAnn -> Doc IdrisAnn
    pChain lvl n [] final = final
    pChain lvl n (l :: ls) final
        = let this = levelLine (lvl == 0) l
              rest : Maybe (Doc IdrisAnn)
              rest = case ls of
                       [] => if isEmptyNotes final then Nothing else Just final
                       _ => if lvl == 2 && n > 4
                               then let skipped = n `minus` 4 in
                                    Just $ reflow ("... and " ++ show skipped ++ " more that match, of which the last:")
                                           <+> line <+> pChain (S lvl) n (drop skipped ls) final
                               else Just (pChain (S lvl) n ls final) in
              maybe this (\ r => this <+> line <+> indent 4 r) rest

perrorRaw (SearchNeeds fc gam n isLocal env g _)
    = do defs <- get Ctxt
         setCtxt gam
         let (_ ** (env', g')) = dropEnv env g
         desc <- candidateDesc fc n isLocal
         gd <- pshow env' g'
         put Ctxt defs
         pure $ errorDesc (desc <++> reflow "needs" <++> code gd <+> dot) <+> line <+> !(ploc fc)

perrorRaw (DeterminingArg fc n i env g)
    = do let res = errorDesc (reflow "Can't find an implementation for" <++> code !(pshow env g) <+> line
                     <+> reflow "since I can't infer a value for argument" <++> code (pretty0 n) <+> dot)
                     <+> line <+> !(ploc fc)
         dflt <- defaultsNote g
         pure $ res <+> line <+> dflt
                <+> reflow "Suggestion: say what it is, with a type annotation such as"
                <++> code "the T e" <+> reflow ", or by giving the implementation with"
                <++> code "@{...}" <+> dot <+> line
perrorRaw (UnsolvedHoles hs)
    = pure $ errorDesc (reflow "Unsolved holes" <+> colon) <+> line <+> !(prettyHoles hs)
  where
    prettyHoles : List (FC, Name) -> Core (Doc IdrisAnn)
    prettyHoles [] = pure emptyDoc
    prettyHoles ((fc, n) :: hs)
        = pure $ meta (pretty0 n) <++> reflow "introduced at:" <++> !(ploc fc) <+> !(prettyHoles hs)
perrorRaw (CantInferArgType fc env n h ty)
    = pure $ errorDesc (reflow "Can't infer type for argument" <++> code (pretty0 n)) <+> line
        <+> "Got" <++> code !(pshow env ty) <++> reflow "with hole" <++> meta (pretty0 h) <+> dot
        <+> line <+> !(ploc fc)
perrorRaw (SolvedNamedHole fc env h tm)
    = pure $ errorDesc (reflow "Named hole" <++> meta (pretty0 h)
        <++> reflow "has been solved by unification.") <+> line
        <+> "Result" <+> colon <++> code !(pshow env tm)
        <+> line <+> !(ploc fc)
perrorRaw (VisibilityError fc vx x vy y)
    = pure $ errorDesc (keyword (pretty0 vx) <++> code (pretty0 (sugarName x))
        <++> reflow "cannot refer to" <++> keyword (pretty0 vy) <++> code (pretty0 (sugarName y)))
        <+> line <+> !(ploc fc)
perrorRaw (NonLinearPattern fc n)
    = pure $ errorDesc (reflow "Non linear pattern" <++> code (pretty0 (sugarName n)) <+> dot)
        <+> line <+> !(ploc fc)
perrorRaw (BadPattern fc n)
    = pure $ errorDesc (reflow "Pattern not allowed here" <+> colon <++> code (pretty0 n) <+> dot)
        <+> line <+> !(ploc fc)
perrorRaw (NoDeclaration fc n)
    = pure $ errorDesc (reflow "No type declaration for" <++> code (pretty0 n) <+> dot)
        <+> line <+> !(ploc fc)
perrorRaw (AlreadyDefined fc n)
    = pure $ errorDesc (code (pretty0 n) <++> reflow "is already defined.")
        <+> line <+> !(ploc fc)
perrorRaw (NotFunctionType fc env tm)
    = pure $ errorDesc (code !(pshow env tm) <++> reflow "is not a function type.")
        <+> line <+> !(ploc fc)
perrorRaw (RewriteNoChange fc env rule ty)
    = pure $ errorDesc (reflow "Rewriting by" <++> code !(pshow env rule)
        <++> reflow "did not change type" <++> code !(pshow env ty) <+> dot)
        <+> line <+> !(ploc fc)
perrorRaw (NotRewriteRule fc env rule)
    = pure $ errorDesc (code !(pshow env rule) <++> reflow "is not a rewrite rule type.")
        <+> line <+> !(ploc fc)
perrorRaw (CaseCompile fc n DifferingArgNumbers)
    = pure $ errorDesc (reflow "Patterns for" <++> code (pretty0 !(prettyName n))
       <++> reflow "have differing numbers of arguments.")
        <+> line <+> !(ploc fc)
perrorRaw (CaseCompile fc n DifferingTypes)
    = pure $ errorDesc (reflow "Patterns for" <++> code (pretty0 !(prettyName n))
       <++> reflow "require matching on different types.")
        <+> line <+> !(ploc fc)
perrorRaw (CaseCompile fc n UnknownType)
    = pure $ errorDesc (reflow "Can't infer type to match in"
       <++> code (pretty0 !(prettyName n)) <+> dot)
        <+> line <+> !(ploc fc)
perrorRaw (CaseCompile fc n (NotFullyApplied cn))
    = pure $ errorDesc ("Constructor" <++> code (pretty0 cn) <++> reflow "is not fully applied.")
         <+> line <+> !(ploc fc)
perrorRaw (CaseCompile fc n (MatchErased (_ ** (env, tm))))
    = pure $ errorDesc (reflow "Attempt to match on erased argument" <++> code !(pshow env tm) <++> "in"
        <++> code (pretty0 !(prettyName n)) <+> dot) <+> line <+> !(ploc fc)
perrorRaw (BadDotPattern fc env reason x y)
    = pure $ errorDesc (reflow "Can't match on" <++> code !(pshow env x)
        <++> parens (pretty reason) <+> dot) <+> line <+> !(ploc fc)
perrorRaw (LiteralNotMatchable fc env lit conv ty)
    = pure $ errorDesc (reflow "Can't match on the" <++> pretty0 (litKind lit)
        <++> code (pretty0 (show lit)) <++> reflow "of type" <++> code !(pshow env ty)
        <+> colon <++> code (pretty0 (nameRoot conv)) <++> reflow "for this type does not reduce to a constructor form."
        ) <+> line <+> !(ploc fc)
        <+> line <+> reflow "Suggestion: match a variable and compare it with == instead."
  where
    litKind : Constant -> String
    litKind (Str _) = "string literal"
    litKind (Ch _) = "character literal"
    litKind (Db _) = "floating point literal"
    litKind _ = "integer literal"
perrorRaw (MatchTooSpecific fc env tm)
    = pure $ errorDesc (reflow "Can't match on" <++> code !(pshow env tm)
        <++> reflow "as it must have a polymorphic type.") <+> line <+> !(ploc fc)
perrorRaw (BadImplicit fc str)
    = pure $ errorDesc (reflow "Can't infer type for unbound implicit name" <++> code (pretty0 str) <+> dot)
        <+> line <+> !(ploc fc) <+> line <+> reflow "Suggestion: try making it a bound implicit."
perrorRaw (BadRunElab fc env script desc)
    = pure $ errorDesc (reflow "Bad elaborator script" <++> code !(pshow env script)
       <++> parens (pretty0 desc) <+> dot)
        <+> line <+> !(ploc fc)
        <+> !(let scriptFC = getLoc script in
          if isJust (isNonEmptyFC scriptFC)
            then pure $ line <+> reflow "Stuck place in the script:" <+> line <+> !(ploc scriptFC)
            else pure emptyDoc)
perrorRaw (RunElabFail e)
    = pure $ reflow "Error during reflection" <+> colon <++> !(perrorRaw e)
perrorRaw (GenericMsg fc str) = pure $ pretty0 str <+> line <+> !(ploc fc)
perrorRaw (GenericMsgTerm fc env before tm after)
    = pure $ errorDesc (reflow before <++> code !(pshow env tm) <+> pretty0 after)
        <+> line <+> !(ploc fc)
perrorRaw (GenericMsgSol fc header solutionHeader solutions)
    = pure $ pretty0 header <+> line <+> !(ploc fc)
       <+> line
       <+> fromString "\{solutionHeader}:" <+> line
       <+> indent 1 (vsep (map (\s => "-" <++> pretty0 s) solutions))
perrorRaw (OperatorBindingMismatch fc {print=p} expected actual opName rhs candidates)
    = pure $ "Operator" <++> pretty0 !(getFullName (fromEither opName)) <++> "is"
       <++> printBindingInfo expected-- .bindingInfo
       <++> "operator, but is used as" <++> printBindingModifier actual.getBinder
       <++> "operator."
       <+> line <+> !(ploc fc)
       <+> "Explanation: regular, typebind and autobind operators all use a slightly different"
       <++> "syntax, typebind looks like this: '(name : type)" <++> infixOpName
       <++> "expr', autobind looks like this: '(name <- expr)" <++> infixOpName
       <++> "expr'."
       <+> line <+> line
       <+> "Possible solutions:" <+> line
       <+> indent 1 (vsep (map ("-" <++>)
           (expressionDiagnositc ++ [fixityDiagnostic, moduleDiagnostic] ++ spellingCandidates)))
    where
      spellingCandidates : List (Doc IdrisAnn)
      spellingCandidates = case candidates of
                              [] => []
                              [x] => ["Did you mean" <++> enclose "'" "'" (pretty0 x) <++> "?"]
                              xs => ["Did you mean either of:" <++> hcat (punctuate ", "
                                       (map (enclose "'" "'" . pretty0) xs)) <++> "?"]


      moduleDiagnostic : Doc IdrisAnn
      moduleDiagnostic = case expected of
                              UndeclaredFixity => "Import a module that exports a suitable fixity."
                              (DeclaredFixity e) => "Hide or remove the fixity at" <++> byShow e.fc
                                  <++> "and import a module that exports a compatible fixity."

      infixOpName : Doc IdrisAnn
      infixOpName = case opName of
                         Left backtickedOp => enclose "`" "`" (byShow backtickedOp)
                         Right symbolOp => byShow symbolOp

      displayFixityInfo : FixityInfo -> BindingModifier -> Doc IdrisAnn
      displayFixityInfo (MkFixityInfo fc1 vis _ fix precedence) NotBinding
        = byShow vis <++> byShow fix <++> byShow precedence <++> pretty0 (fromEither opName)
      displayFixityInfo (MkFixityInfo _ vis _ fix precedence) usedBinder
        = byShow vis <++> byShow usedBinder <++> byShow fix <++> byShow precedence <++> pretty0 (fromEither opName)

      printE : ? -> Doc IdrisAnn
      printE x = reAnnotate (const Code) (p x)

      expressionDiagnositc : List (Doc IdrisAnn)
      expressionDiagnositc = case expected of
          UndeclaredFixity => []
          DeclaredFixity e => let sentence = "Write the expression using" <++> byShow e.bindingInfo <++> "syntax:"
            in pure $ sentence <++> enclose "'" "'" (case e.bindingInfo of
                    NotBinding =>
                       printE actual.getLhs <++> infixOpName <++> printE rhs
                    Autobind =>
                       parens (maybe "_" printE actual.getBoundPat <++> "<-"
                               <++> printE actual.getLhs)
                       <++> infixOpName <++> printE rhs
                    Typebind =>
                       parens (maybe "_" printE actual.getBoundPat <++> ":"
                               <++> printE actual.getLhs)
                       <++> infixOpName <++> printE rhs
                    ) <+> dot


      fixityDiagnostic : Doc IdrisAnn
      fixityDiagnostic = case expected of
           UndeclaredFixity => "Define a new fixity:" <++> "infixr 0" <++> infixOpName
           (DeclaredFixity fix) =>
            "Change the fixity defined at" <++> pretty0 fix.fc <++> "to"
            <++> enclose "'" "'" (displayFixityInfo fix actual.getBinder)
            <+> dot

      printBindingModifier : BindingModifier -> Doc IdrisAnn
      printBindingModifier NotBinding = "a regular"
      printBindingModifier Typebind = "a type-binding (typebind)"
      printBindingModifier Autobind = "an automatically-binding (autobind)"

      printBindingInfo : FixityDeclarationInfo -> Doc IdrisAnn
      printBindingInfo UndeclaredFixity = "a regular"
      printBindingInfo (DeclaredFixity x) = printBindingModifier x.bindingInfo


perrorRaw (TTCError msg)
    = pure $ errorDesc (reflow "Error in TTC file" <+> colon <++> byShow msg)
        <++> parens "the most likely case is that the ./build directory in your current project contains files from a previous build of idris2 or the idris2 executable is from a different build than the installed .ttc files"
perrorRaw (FileErr fname err)
    = pure $ errorDesc (reflow "File error in" <++> pretty0 fname <++> colon)
       <++> byShow err
perrorRaw (CantFindPackage fname)
    = pure $ errorDesc (reflow "Can't find package " <++> pretty0 fname)
perrorRaw (LazyImplicitFunction fc)
    = pure $ errorDesc (reflow "Implicit lazy functions are not yet supported.") <+> line <+> !(ploc fc)
perrorRaw (LazyPatternVar fc)
    = pure $ errorDesc (reflow "Defining lazy functions via pattern matching is not yet supported.") <+> line <+> !(ploc fc)
perrorRaw (LitFail fc)
    = pure $ errorDesc (reflow "Can't parse literate.")
        <+> line <+> !(ploc fc)
perrorRaw (LexFail fc msg)
    = pure $ errorDesc (pretty0 msg) <+> line <+> !(ploc fc)
perrorRaw (ParseFail ((fc, msg) ::: Nil))
    = pure $ errorDesc (pretty0 msg) <+> line <+> !(ploc fc)
perrorRaw (ParseFail errs)
    = pure $ errorDesc (reflow "Couldn't parse any alternatives" <+> colon) <+> line <+> !listErrors
  where
    prettyErrors : Nat -> Nat -> List (FC, String) -> Core (Doc IdrisAnn)
    prettyErrors showCount _ []   = pure emptyDoc
    prettyErrors showCount 0 errs = pure $ meta (pretty0 "... (\{show $ length errs} others)")
    prettyErrors showCount (S k) ((fc, msg) :: hs)
        = do let idx = show $ showCount `minus` k
             pure $ warning (pretty0 "\{idx}: \{msg}")
               <+> line <+> !(ploc fc)
               <+> !(prettyErrors showCount k hs)

    listErrors : Core (Doc IdrisAnn)
    listErrors = do showCount <- logErrorCount . session . options <$> get Ctxt
                    prettyErrors showCount showCount . nub . reverse $ forget errs
perrorRaw (ModuleNotFound fc ns)
    = pure $ errorDesc ("Module" <++> annotate FileCtxt (pretty0 ns) <++> reflow "not found")
        <+> line <+> !(ploc fc)
perrorRaw (CyclicImports ns)
    = pure $ errorDesc (reflow "Module imports form a cycle" <+> colon)
        <++> concatWith (surround " -> ") (pretty0 <$> ns)
perrorRaw ForceNeeded = pure $ errorDesc (reflow "Internal error when resolving implicit laziness")
perrorRaw (InternalError str) = pure $ errorDesc (reflow "INTERNAL ERROR" <+> colon) <++> pretty0 str
perrorRaw (UserError str) = pure . errorDesc $ pretty0 str
perrorRaw (NoForeignCC fc specs) = do
    let cgs = fst <$> availableCGs (options !(get Ctxt))
    let res = vsep [ errorDesc (reflow ("The given specifier '" ++ show specs ++ "' was not accepted by any backend. Available backends") <+> colon)
                   , indent 2 (concatWith (\ x, y => x <+> ", " <+> y) (map reflow cgs))
                   , reflow "Some backends have additional specifier rules, refer to their documentation."
                   ] <+> line <+> !(ploc fc)
    pure res
perrorRaw (BadMultiline fc str)
  = pure $ errorDesc (reflow "While processing multi-line string" <+> dot <++> pretty0 str <+> dot)
      <+> line <+> !(ploc fc)
perrorRaw (Timeout str) = pure $ errorDesc (reflow "Timeout in" <++> pretty0 str)

perrorRaw (FailingDidNotFail fc)
  = pure $ errorDesc (reflow "Failing block did not fail" <+> dot)
    <+> line <+> !(ploc fc)
perrorRaw (FailingWrongError fc msg err)
  = pure $ vcat [ errorDesc (reflow "Failing block failed with the wrong error" <+> dot)
                , "Expected" <++> dquote <+> pretty0 msg <+> dquote <++> "but got:"
                , vsep !(traverse perrorRaw (forget err))
                ]

perrorRaw (InType fc n err)
    = pure $ hsep [ errorDesc (reflow "While processing type of" <++> code (pretty0 !(prettyName n))) <+> dot
                  , !(inDefinition n (perrorRaw err))
                  ]
perrorRaw (InCon n err)
    = pure $ hsep [ errorDesc (reflow "While processing constructor" <++> code (pretty0 !(prettyName n.val))) <+> dot
                  , !(inDefinition n.val (perrorRaw err))
                  ]
perrorRaw (InLHS fc n err)
    = pure $ hsep [ errorDesc (reflow "While processing left hand side of" <++> code (pretty0 !(prettyName n))) <+> dot
                  , !(inDefinition n (perrorRaw err))
                  ]
perrorRaw (InRHS fc n err)
    = pure $ hsep [ errorDesc (reflow "While processing right hand side of" <++> code (pretty0 !(prettyName n))) <+> dot
                  , !(inDefinition n (perrorRaw err))
                  ]

perrorRaw (QuantitiesChosen fc n chs err)
    = pure $ !(perrorRaw err) <+> line
        <+> reflow "The quantities of" <++> code (pretty0 !(prettyName n)) <++> reflow "were chosen as"
        <++> concatWith (surround (comma <+> space)) !(traverse choice chs)
        <+> dot <++> reflow "Write them at the reference to choose others, as in"
        <++> code (pretty0 !(prettyName n) <++> braces (pretty0 (exampleVar chs) <++> equals <++> pretty0 (exampleRig chs))) <+> dot
  where
    exampleVar : List QuantityChoice -> String
    exampleVar (ch :: _) = show (chVar ch)
    exampleVar [] = "%q"

    -- the other quantity than the one chosen
    exampleRig : List QuantityChoice -> String
    exampleRig (ch :: _) = if isOne (chRig ch) then "omega" else "1"
    exampleRig [] = "1"

    rigText : RigCount -> String
    rigText r = elimSemi "0" "1" (\r => maybe "unrestricted" id (showVarsCount r)) r

    choice : QuantityChoice -> Core (Doc IdrisAnn)
    choice ch
        = do why <- the (Core String) $ case chWhy ch of
                         QWritten => pure "as written"
                         QFromExpected => pure "from the expected type"
                         QFromArgument i => pure ("from the type of argument " ++ show i)
                         QFromBinder x => pure ("because " ++ show x ++ " is bound at that quantity")
                         QByDefault => pure "by default"
             pure (code (pretty0 (show (chVar ch) ++ " = " ++ rigText (chRig ch))) <++> parens (pretty0 why))

perrorRaw (MaybeMisspelling err ns)
    = do -- the definitions the message is about are not what was meant
         defs <- defining <$> get MsgNames
         let ns = filter (\ s => not (any (spelt s) defs)) (forget ns)
         pure $ !(perrorRaw err) <+> case ns of
           [] => emptyDoc
           [n] => reflow "Did you mean:" <++> code (pretty0 n) <+> "?"
           [m, n] => reflow "Did you mean:" <++> code (pretty0 m) <++> "or"
                       <++> code (pretty0 n) <+> "?"
           (n :: ns) =>
             let (xs, x) = unsnoc (n ::: ns) in
             reflow "Did you mean any of:"
             <++> concatWith (surround (comma <+> space)) (map (code . pretty0) xs)
             <+> comma <++> "or" <++> code (pretty0 x) <+> "?"
  where
    spelt : String -> Name -> Bool
    spelt s def = s == nameRoot def || s == show def
perrorRaw (WarningAsError warn) = pwarningRaw warn

export
perror : {auto c : Ref Ctxt Defs} ->
         {auto s : Ref Syn SyntaxInfo} ->
         {auto o : Ref ROpts REPLOpts} ->
         Error -> Core (Doc IdrisAnn)
perror err
    = do mnames <- newRef MsgNames initMsgNames
         distinctNames (perrorRaw !(toFullNames err))

||| What a JSON diagnostic says about an error beyond its location and its
||| message (see `docs/source/tutorial/interactive.rst` for the fields)
public export
record DiagnosticInfo where
  constructor MkDiagnosticInfo
  code : String
  ||| The first line of the message, without the context
  headline : String
  ||| Where the error was found ("While processing right hand side of f"),
  ||| outermost first
  context : List String
  ||| For a mismatch between the type of an expression and the type its
  ||| context expects: the two types
  expected : Maybe String
  got : Maybe String
  ||| The candidates of a failed overloaded name, or of an ambiguous search:
  ||| a name, a location, and why it failed or what it is
  candidates : List (Maybe String, FC, String)
  ||| Other places that the message is about, each with what it is
  related : List (FC, String)
  ||| Names that were maybe meant (`Left`), and modules to import, with the
  ||| import line (`Right`)
  suggestions : List (Either String (String, String))
  ||| The lines of the message after its headline
  notes : List String

||| Render a document on one line as far as it goes, without colours
plainUnbounded : Doc IdrisAnn -> String
plainUnbounded doc = renderString $ unAnnotateS $ layoutPretty (MkLayoutOptions Unbounded) doc

||| A message as its headline (its first line) and the other lines that are
||| not blank
headlineAndNotes : String -> (String, List String)
headlineAndNotes msg
    = case filter (not . null) (map trim (lines msg)) of
           [] => ("", [])
           (h :: rest) => (h, rest)

||| A term as the user would write it, without any note on where its
||| variable is bound
pshowBare : {vars : _} ->
            {auto c : Ref Ctxt Defs} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto mnames : Ref MsgNames MsgNameState} ->
            Env Term vars -> Term vars -> Core String
pshowBare env tm
    = do defs <- get Ctxt
         ntm <- normaliseHoles defs env tm
         itm <- resugarMsg env ntm
         pure (plainUnbounded (prettyBy Syntax itm))

||| Where a variable that the compiler bound is bound, if a term is one
boundAt : {vars : _} -> Env Term vars -> Term vars -> String -> List (FC, String)
boundAt env (Local _ _ _ p) what
    = case dropAllNS (nameAt p) of
           MN {} => [(getBinderLoc p env, what ++ " implicitly bound here")]
           _ => []
boundAt _ _ _ = []

export
diagnosticInfo : {auto c : Ref Ctxt Defs} ->
                 {auto s : Ref Syn SyntaxInfo} ->
                 {auto o : Ref ROpts REPLOpts} ->
                 Error -> Core DiagnosticInfo
diagnosticInfo err_in
    = do mnames <- newRef MsgNames initMsgNames
         err <- toFullNames err_in
         distinctNames (info err)
  where
    -- the context of an error, and the error without it
    addCtx : String -> Name -> (List String, List (Either String (String, String)), Error) ->
             Core (List String, List (Either String (String, String)), Error)
    addCtx what n (c, sg, e')
        = do nm <- prettyName n
             pure ((what ++ " " ++ nm) :: c, sg, e')

    unwrap : Error -> Core (List String, List (Either String (String, String)), Error)
    unwrap (Fatal e) = unwrap e
    unwrap (InType _ n e) = addCtx "While processing type of" n !(unwrap e)
    unwrap (InCon n e) = addCtx "While processing constructor" n.val !(unwrap e)
    unwrap (InLHS _ n e) = addCtx "While processing left hand side of" n !(unwrap e)
    unwrap (InRHS _ n e) = addCtx "While processing right hand side of" n !(unwrap e)
    unwrap (MaybeMisspelling e ns)
        = do (c, sg, e') <- unwrap e
             pure (c, sg ++ map Left (forget ns), e')
    unwrap (QuantitiesChosen _ _ _ e) = unwrap e
    unwrap e = pure ([], [], e)

    innermost : Error -> Error
    innermost (WhenUnifying _ _ _ _ _ _ _ e) = innermost e
    innermost (Fatal e) = innermost e
    innermost e = e

    render : {auto mnames : Ref MsgNames MsgNameState} -> Error -> Core String
    render e = plainUnbounded <$> perrorRaw e

    labelled : {auto mnames : Ref MsgNames MsgNameState} ->
               Error -> Core (Maybe String, Maybe String, List (FC, String))
    -- where the variables of an inner mismatch that the compiler bound are
    -- bound
    innerBound : Error -> List (FC, String)
    innerBound (WhenUnifying _ _ _ _ _ _ _ e) = innerBound e
    innerBound (CantConvert _ _ env x y) = boundAt env x "variable" ++ boundAt env y "variable"
    innerBound (CantSolveEq _ _ env x y _) = boundAt env x "variable" ++ boundAt env y "variable"
    innerBound _ = []

    labelled (WhenUnifying _ GotExpected gam env x y inferred inner)
        = do defs <- get Ctxt
             setCtxt gam
             got <- pshowBare env x
             exp <- pshowBare env y
             sols <- traverse (\ (m, sfc, v) =>
                                 do md <- pshowNoNorm env m
                                    vd <- pshowBare env v
                                    let mname = trim (fst (break (== '[') (show md)))
                                    pure (sfc, "inferred " ++ mname ++ " = " ++ vd)) inferred
             put Ctxt defs
             pure (Just exp, Just got, boundAt env y "expected type" ++ boundAt env x "type"
                                         ++ innerBound inner ++ sols)
    labelled (WhenUnifying _ Unordered gam env x y inferred inner)
        = do defs <- get Ctxt
             setCtxt gam
             sols <- traverse (\ (m, sfc, v) =>
                                 do md <- pshowNoNorm env m
                                    vd <- pshowBare env v
                                    let mname = trim (fst (break (== '[') (show md)))
                                    pure (sfc, "inferred " ++ mname ++ " = " ++ vd)) inferred
             put Ctxt defs
             pure (Nothing, Nothing, innerBound inner ++ sols)
    labelled e@(CantConvert {}) = pure (Nothing, Nothing, innerBound e)
    labelled _ = pure (Nothing, Nothing, [])

    -- the candidates of a failed overload or of an ambiguous search
    candidatesOf : {auto mnames : Ref MsgNames MsgNameState} ->
                   Error -> Core (List (Maybe String, FC, String))
    candidatesOf (AllFailed _ ts)
        = for ts $ \ (mn, e) =>
            do nm <- traverseOpt (\ n => do n' <- aliasName !(getFullName n)
                                            pure (show n')) mn
               (_, _, e') <- unwrap e
               reason <- fst . headlineAndNotes <$> render (killErrorLoc (innermost e'))
               pure (nm, fromMaybe emptyFC (getErrorLoc (innermost e')), reason)
    candidatesOf (AmbiguousSearch fc env _ ts)
        = for ts $ \ t =>
            do defs <- get Ctxt
               let (Ref _ _ n, _) = getFnArgs t
                 | _ => do d <- pshowBare env t
                           pure (Just d, getLoc t, "a local solution")
               Just gdef <- lookupCtxtExact n (gamma defs)
                 | Nothing => pure (Just (show n), emptyFC, "a solution")
               ty <- pshowBare Env.empty (type gdef)
               if isUnnamedImpl (fullname gdef)
                  then pure (Nothing, location gdef, "the implementation " ++ ty)
                  else do nm <- prettyName (fullname gdef)
                          pure (Just nm, location gdef, "the implementation " ++ nm ++ " : " ++ ty)
    candidatesOf _ = pure []

    -- the implementations of a chain of needed sub-goals
    needs : {auto mnames : Ref MsgNames MsgNameState} ->
            Maybe Error -> Core (List (FC, String))
    needs (Just (SearchNeeds _ gam n False env g cause))
        = do defs <- get Ctxt
             setCtxt gam
             Just gdef <- lookupCtxtExact n (gamma defs)
               | Nothing => do put Ctxt defs; needs cause
             ty <- pshowBare Env.empty (type gdef)
             let (_ ** (env', g')) = dropEnv env g
             sg <- pshowBare env' g'
             put Ctxt defs
             rest <- needs cause
             pure ((location gdef, "the implementation " ++ ty ++ ", which needs " ++ sg) :: rest)
    needs (Just (SearchNeeds _ _ _ True _ _ cause)) = needs cause
    needs _ = pure []

    relatedOf : {auto mnames : Ref MsgNames MsgNameState} ->
                Error -> Core (List (FC, String))
    relatedOf (CantSolveGoal _ _ _ _ cause) = needs cause
    relatedOf (NotTotal _ n r)
        = do calls <- case onceRound r of
                        RecPath loop => pure loop
                        BadPath init _ => pure init
                        BadCall ns => callsTo n ns
                        _ => pure []
             for calls $ \ (cfc, cn) => pure (cfc, "call to " ++ !(prettyName cn))
    relatedOf (NotCovering _ n (NonCoveringCall ns))
        = do calls <- callsTo n ns
             for calls $ \ (cfc, cn) => pure (cfc, "call to " ++ !(prettyName cn))
    relatedOf _ = pure []

    imports : Error -> Core (List (Either String (String, String)))
    imports (UndefinedName _ n)
        = do ms <- catch (importCandidates n) (\_ => pure [])
             pure (map (\ (m, _) => Right (m, "import " ++ m)) ms)
    imports _ = pure []

    info : {auto mnames : Ref MsgNames MsgNameState} -> Error -> Core DiagnosticInfo
    info err
        = do (context, misspelt, core) <- unwrap err
             (hd, notes) <- headlineAndNotes <$> render (innermost core)
             (hd, notes) <- case core of
                              -- the lines of a labelled mismatch, after its headline
                              WhenUnifying {} => do (_, ns) <- headlineAndNotes <$> render core
                                                    pure (hd, filter (/= hd) ns)
                              _ => pure (hd, notes)
             (exp, got, rel) <- labelled core
             cands <- candidatesOf (innermost core)
             rel' <- relatedOf (innermost core)
             imps <- imports (innermost core)
             pure $ MkDiagnosticInfo (errorCode err) hd context exp got cands
                                     (rel ++ rel') (misspelt ++ imps) notes

export
warningDiagnosticInfo : {auto c : Ref Ctxt Defs} ->
                        {auto s : Ref Syn SyntaxInfo} ->
                        {auto o : Ref ROpts REPLOpts} ->
                        Warning -> Core DiagnosticInfo
warningDiagnosticInfo (ErrorWarning err) = diagnosticInfo err
warningDiagnosticInfo w
    = do mnames <- newRef MsgNames initMsgNames
         msg <- plainUnbounded <$> distinctNames (pwarningRaw !(toFullNames w))
         let (hd, notes) = headlineAndNotes msg
         rel <- case w of
                  Deprecated _ _ (Just (dfc, _)) => pure [(dfc, "the deprecated definition")]
                  _ => pure []
         pure $ MkDiagnosticInfo (warningCode w) hd [] Nothing Nothing [] rel [] notes

||| Check (in a whitespace-insensitive manner) that the msg is
||| contained in the error.
export
checkError :
  {auto c : Ref Ctxt Defs} ->
  {auto s : Ref Syn SyntaxInfo} ->
  {auto o : Ref ROpts REPLOpts} ->
  (msg : String) -> Error -> Core Bool
checkError msg err = do
  -- Kill the locations so that we don't get source code excerpts
  let err = killErrorLoc err
  -- Show the error as a string
  str <- show <$> perror err
  -- Normalise the two strings. This ensures comparison is whitespace
  -- insentitive (error messages' layout depend on terminal width)
  let msg = unwords (words msg)
  let str = unwords (words str)
  pure (msg `isInfixOf` str)

prettyMaybeLoc : Maybe FC -> Doc IdrisAnn
prettyMaybeLoc Nothing = emptyDoc
prettyMaybeLoc (Just fc) = annotate FileCtxt (pretty0 fc) <+> colon

||| Whether a document has a line break that is not undone when it is laid
||| out (a hard line, or a `line` that is not grouped)
hasBreak : Doc ann -> Bool
hasBreak Line = True
hasBreak (FlatAlt x _) = hasBreak x
hasBreak (Cat x y) = hasBreak x || hasBreak y
hasBreak (Nest _ d) = hasBreak d
hasBreak (Annotated _ d) = hasBreak d
hasBreak _ = False

||| Put a document at the end of the first line of another
endOfFirstLine : Doc ann -> Doc ann -> Doc ann
endOfFirstLine s doc = if hasBreak doc then before doc else doc <+> s
  where
    before : Doc ann -> Doc ann
    before Line = s <+> Line
    before (FlatAlt x y) = FlatAlt (before x) y
    before (Cat x y) = if hasBreak x then Cat (before x) y else Cat x (before y)
    before (Nest i d) = Nest i (before d)
    before (Annotated a d) = Annotated a (before d)
    before d = d <+> s

||| The code of an error or a warning, in brackets at the end of the first
||| line of its message, unless `--no-error-codes` is given. It is only in
||| the message as it is displayed: `failing` blocks, JSON diagnostics (which
||| have it as a field) and the IDE mode do not see it.
withCode : {auto c : Ref Ctxt Defs} -> String -> Doc IdrisAnn -> Core (Doc IdrisAnn)
withCode code doc
    = if (errorCodes !getSession)
         then pure (endOfFirstLine (space <+> brackets (pretty0 code)) doc)
         else pure doc

export
display : {auto c : Ref Ctxt Defs} ->
          {auto s : Ref Syn SyntaxInfo} ->
          {auto o : Ref ROpts REPLOpts} ->
          Error -> Core (Doc IdrisAnn)
display err = do
  withCode (errorCode err) $ annotate Error "Error:" <++> !(perror err)

export
displayWarning : {auto c : Ref Ctxt Defs} ->
                 {auto s : Ref Syn SyntaxInfo} ->
                 {auto o : Ref ROpts REPLOpts} ->
                 Warning -> Core (Doc IdrisAnn)
displayWarning w
    = withCode (warningCode w) $ annotate Warning "Warning:" <++> !(pwarning w)
