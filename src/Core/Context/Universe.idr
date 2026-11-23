||| The universe constraint graph used by `--check-universes`.
|||
||| Every `Type` in an elaborated term carries a name standing for its
||| universe level. The universe checker (Core.UniverseCheck) generates
||| constraints `u <= v` and `u < v` between these names, and this module
||| keeps them in a graph. The constraints are satisfiable by natural numbers
||| exactly when no cycle in the graph contains a strict edge: there are no
||| upper bounds, so the size of a strict step does not matter, only whether
||| a cycle has one.
|||
||| To find such a cycle cheaply when an edge is added, the graph keeps an
||| assignment of levels which satisfies every edge added so far. Adding
||| `lo -w-> hi` (meaning `hi >= lo + w`, w being 0 or 1) raises `hi` and
||| whatever is above it as far as needed. Since the graph was consistent
||| before, a new cycle with a strict edge has to go through the new edge,
||| and the raising reaches `lo` exactly when there is one.
module Core.Context.Universe

import Core.FC
import Core.Name

import Data.List
import Data.Maybe
import Libraries.Data.NameMap

%default covering

||| An edge `lo <= hi` (or `lo < hi` when strict), with the name of the
||| definition whose checking produced it, for error messages.
public export
record UEdge where
  constructor MkUEdge
  lo : Name
  hi : Name
  strict : Bool
  origin : Name

export
Show UEdge where
  show e = show e.lo ++ (if e.strict then " < " else " <= ") ++ show e.hi
           ++ " (" ++ show e.origin ++ ")"

public export
record UGraph where
  constructor MkUGraph
  succs : NameMap (List UEdge)
  levels : NameMap Nat

||| The names of a list without repetitions, in the order of their first
||| occurrence
export
nubNames : List Name -> List Name
nubNames = go empty
  where
    go : NameMap () -> List Name -> List Name
    go seen [] = []
    go seen (n :: ns)
        = if isJust (lookup n seen) then go seen ns else n :: go (insert n () seen) ns

||| A set of names, for membership tests
export
nameSet : List Name -> NameMap ()
nameSet = foldl (\ m, n => insert n () m) empty

export
emptyUGraph : UGraph
emptyUGraph = MkUGraph empty empty

level : UGraph -> Name -> Nat
level g n = fromMaybe 0 (lookup n g.levels)

weight : UEdge -> Nat
weight e = if e.strict then 1 else 0

outEdges : UGraph -> Name -> List UEdge
outEdges g n = fromMaybe [] (lookup n g.succs)

-- Breadth first search for a path from 'from' to 'to', returning the
-- edges of the path. 'needStrict' says whether the path must contain a
-- strict edge. The search is over pairs of a node and whether a strict
-- edge has been seen on the way there.
findPath : UGraph -> (from, to : Name) -> (needStrict : Bool) ->
           Maybe (List UEdge)
findPath g from to needStrict
    = go [(from, False, [])] (insert from [False] empty)
  where
    seen : Name -> Bool -> NameMap (List Bool) -> Bool
    seen n s vis = maybe False (elem s) (lookup n vis)

    mark : Name -> Bool -> NameMap (List Bool) -> NameMap (List Bool)
    mark n s vis = insert n (s :: fromMaybe [] (lookup n vis)) vis

    go : List (Name, Bool, List UEdge) -> NameMap (List Bool) ->
         Maybe (List UEdge)
    go [] _ = Nothing
    go ((n, s, path) :: rest) vis
        = if n == to && (s || not needStrict)
             then Just (reverse path)
             else let (next, vis') = step (outEdges g n) [] vis in
                      go (rest ++ next) vis'
      where
        step : List UEdge -> List (Name, Bool, List UEdge) ->
               NameMap (List Bool) ->
               (List (Name, Bool, List UEdge), NameMap (List Bool))
        step [] acc vis = (reverse acc, vis)
        step (e :: es) acc vis
            = let s' = s || e.strict in
                  if seen e.hi s' vis
                     then step es acc vis
                     else step es ((e.hi, s', e :: path) :: acc)
                               (mark e.hi s' vis)

||| Add an edge, returning a cycle with a strict edge (as a list of edges)
||| if the graph becomes inconsistent.
export
addUEdge : UEdge -> UGraph -> Either (List UEdge) UGraph
addUEdge e g
    = if e.lo == e.hi
         then if e.strict then Left [e] else Right g
         else let g' = { succs $= insert e.lo (e :: outEdges g e.lo) } g
                  need = level g e.lo + weight e in
                  if level g e.hi >= need
                     then Right g'
                     else raise [e.hi] ({ levels $= insert e.hi need } g')
  where
    cycle : UGraph -> List UEdge
    cycle g = case findPath g e.hi e.lo (not e.strict) of
                   Just p => e :: p
                   Nothing => [e] -- can't happen

    raise : List Name -> UGraph -> Either (List UEdge) UGraph
    raise [] g = Right g
    raise (x :: todo) g = edges (outEdges g x) todo g
      where
        edges : List UEdge -> List Name -> UGraph -> Either (List UEdge) UGraph
        edges [] todo g = raise todo g
        edges (o :: os) todo g
            = let need = level g x + weight o in
                  if level g o.hi >= need
                     then edges os todo g
                     else if o.hi == e.lo
                             then Left (cycle g)
                             else edges os (o.hi :: todo)
                                        ({ levels $= insert o.hi need } g)

export
addUEdges : List UEdge -> UGraph -> Either (List UEdge) UGraph
addUEdges [] g = Right g
addUEdges (e :: es) g = addUEdge e g >>= addUEdges es

||| Project the edges of one definition onto the names which are not
||| local to its check (those for which 'isLocal' is False): every path
||| between two such names through local names becomes an edge, strict if
||| any edge on the path is strict. Satisfiability of the whole graph is
||| unchanged, since the local names are never mentioned again.
export
projectUEdges : (isLocal : Name -> Bool) -> (origin : Name) ->
                List UEdge -> List UEdge
projectUEdges isLocal origin es
    = let adj = foldl (\m, e => insert e.lo (e :: fromMaybe [] (lookup e.lo m)) m)
                      empty es
          srcs = nubNames (filter (not . isLocal) (map lo es)) in
          concatMap (fromSource adj) srcs
  where
    fromSource : NameMap (List UEdge) -> Name -> List UEdge
    fromSource adj src
        = let found = walk [(src, False)] empty empty in
              map (\ (n, s) => MkUEdge src n s origin) (toList found)
      where
        -- 'found' maps reached non-local names to whether a strict path
        -- reaches them; 'vis' records the visited (local name, strict) pairs
        walk : List (Name, Bool) -> NameMap (List Bool) -> NameMap Bool ->
               NameMap Bool
        walk [] vis found = found
        walk ((n, s) :: rest) vis found
            = let outs = fromMaybe [] (lookup n adj) in
                  step outs rest vis found
          where
            step : List UEdge -> List (Name, Bool) -> NameMap (List Bool) ->
                   NameMap Bool -> NameMap Bool
            step [] rest vis found = walk rest vis found
            step (o :: os) rest vis found
                = let s' = s || o.strict in
                      if not (isLocal o.hi)
                         then let old = fromMaybe False (lookup o.hi found) in
                                  step os rest vis (insert o.hi (old || s') found)
                         else if maybe False (elem s') (lookup o.hi vis)
                                 then step os rest vis found
                                 else step os ((o.hi, s') :: rest)
                                           (insert o.hi (s' :: fromMaybe [] (lookup o.hi vis)) vis)
                                           found

||| The universe polymorphism of a global definition: the universes which
||| may be renamed at each use, with the constraints its checking put on
||| them. See Core.UniverseCheck for when this is sound.
public export
record USchema where
  constructor MkUSchema
  ||| For a function, in this order, the universes which an instance of a
  ||| reference to it names (see Func in Core.TT.Term); for a type
  ||| constructor, those of them which are in 'instOnly' (see TyCon)
  poly : List Name
  edges : List UEdge
  ||| The universes of 'poly' which are renamed only through an instance:
  ||| those in the fields of a data type. A use without an instance keeps
  ||| them (and renames the others).
  instOnly : List Name
  ||| When the definition was completed (see 'completions'); -1 for the
  ||| definitions of imported modules
  stamp : Int
  ||| The definitions which share this schema (a definition and the case
  ||| blocks, with blocks and local definitions lifted out of it, or an
  ||| implementation and its methods): a reference from one of them to
  ||| another has no instance, and is renamed with the one it is in
  group : List Name
  ||| Further universes of a function, which a copy does not rename on their
  ||| own: each is renamed as the universe of 'poly' it goes with, or is
  ||| replaced by a universe which is not renamed (see 'minimise' in
  ||| Core.UniverseCheck). The definition's own universes (a reference
  ||| without an instance) are not changed.
  aliases : List (Name, Name)
  ||| For a function: none of these universes are in its clauses (its body),
  ||| only in its type. Then a reference to it needs no instance: unfolding
  ||| it gives the same body whatever the instance, and the checker gives
  ||| its type fresh universes at each use (as for a constructor).
  bodyFree : Bool

||| The renaming of the universes of a function's schema to an instance
||| (which names the universes of 'poly', in order)
export
instPairs : USchema -> List Name -> List (Name, Name)
instPairs sch inst
    = let ps = zip sch.poly inst
          m = addPairs ps empty in
          ps ++ map (\ (a, t) => (a, fromMaybe t (lookup t m))) sch.aliases

  where
    addPairs : List (Name, Name) -> NameMap Name -> NameMap Name
    addPairs [] m = m
    addPairs ((p, u) :: ps) m = addPairs ps (insert p u m)

||| The pairs of universes which two references to a function identify, when
||| one of them has no instance (the function's own universes) and the other
||| has 'inst'
export
ownPairs : USchema -> List Name -> List (Name, Name)
ownPairs sch inst = instPairs sch inst

||| What the universe checker keeps for the module being processed.
public export
record UniverseInfo where
  constructor MkUniverseInfo
  ||| The constraints of this module and of the imported ones
  graph : UGraph
  ||| The constraints this module adds, to save in its TTC file
  saved : List UEdge
  ||| The metavariables whose solutions have been checked
  checkedMetas : NameMap ()
  ||| The metavariables found unsolved, whose solutions (if they get one)
  ||| still have to be checked
  pendingMetas : NameMap ()
  ||| The imported modules whose TTC files were written without checking
  ||| universes
  uncheckedImports : List String
  ||| The universes which can never be renamed: those which evaluation can
  ||| produce (they occur in a definition's body or a metavariable's
  ||| solution) and those inside the fields of constructors
  fixed : NameMap ()
  ||| The universes this module adds to 'fixed', to save in its TTC file
  savedFixed : List Name
  ||| The universe polymorphism of the definitions checked completely
  schemas : NameMap USchema
  ||| The schemas this module adds, to save in its TTC file
  savedSchemas : List (Name, USchema)
  ||| For the definitions of this module being checked: the constraints of
  ||| the checks so far, and whether one of them met an unsolved
  ||| metavariable
  defEdges : NameMap (List UEdge, Bool)
  ||| For each universe in the type or the clauses of a global definition,
  ||| the definitions which have it: a definition can rename it only if they
  ||| all belong to its family (itself, or its data type and constructors)
  ||| or its group (see 'group' in USchema)
  typeOwner : NameMap (List Name)
  ||| What this module adds to 'typeOwner', to save in its TTC file
  savedTypeOwner : List (Name, Name)
  ||| The definitions of this module the check could not finish
  incompleteDefs : List Name
  ||| How many definitions of this module have been made polymorphic
  completions : Int
  ||| For each definition of this module, the value of 'completions' when its
  ||| check started
  defStart : NameMap Int
  ||| The implementation being elaborated, if it is not inside a definition:
  ||| the definitions checked until it is done are one group with it
  implGroup : Maybe Name
  ||| The definitions checked completely whose schemas wait for their group
  ||| to be done, by the name of the group, with their universes
  deferred : NameMap (List (Name, List Name))

export
initUniverseInfo : UniverseInfo
initUniverseInfo
    = MkUniverseInfo emptyUGraph [] empty empty [] empty [] empty [] empty empty [] [] 0 empty
                     Nothing empty
