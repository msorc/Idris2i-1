||| A solver for equalities of natural numbers, by reflection.
|||
||| `solveNat` proves a goal `lhs = rhs` between two expressions built from
||| variables (or any other term it does not know, an "atom"), literals,
||| `S`, `+` and `*`, when the two sides are equal in every commutative
||| semiring, that is, when they have the same normal form as polynomials:
|||
||| ```idris
||| example : (x, y, z : Nat) -> (x + y) * (z + 1) = x * z + y + z * y + x
||| example x y z = solveNat
||| ```
|||
||| The proof is `prove env lhs rhs Refl`: `norm` computes the normal forms
||| of the reified sides, and `normSound` proves once and for all that the
||| normal form evaluates to the same number as the expression. Type checking
||| `Refl` computes both normal forms, with unary coefficients, so the cost
||| grows with the size of the coefficients of the polynomials.
|||
||| Subtraction, division and the other functions are not interpreted: an
||| application such as `minus x y` is an atom, compared syntactically after
||| normalisation.
module Data.Nat.Solver

import public Language.Reflection

import Data.Nat
import Syntax.PreorderReasoning

%default total
%language ElabReflection

------------------------------------------------------------------------------
-- Expressions

||| Expressions of the commutative semiring of natural numbers. Variables are
||| indices in an environment.
public export
data Expr : Type where
  Var  : (i : Nat) -> Expr
  Lit  : (n : Nat) -> Expr
  Plus : Expr -> Expr -> Expr
  Mult : Expr -> Expr -> Expr

||| The value of a variable; a variable which is not in the environment is 0
public export
lookupVar : List Nat -> Nat -> Nat
lookupVar [] _ = 0
lookupVar (x :: _) Z = x
lookupVar (_ :: xs) (S i) = lookupVar xs i

public export
eval : List Nat -> Expr -> Nat
eval env (Var i) = lookupVar env i
eval env (Lit n) = n
eval env (Plus a b) = eval env a + eval env b
eval env (Mult a b) = eval env a * eval env b

------------------------------------------------------------------------------
-- Normal forms: polynomials

||| A monomial: the indices of its variables, in increasing order, repeated
||| for powers (x * x * y is [0, 0, 1])
public export
Mono : Type
Mono = List Nat

||| A polynomial: monomials with their (non-zero) coefficients, in increasing
||| order of monomials, each monomial once
public export
Poly : Type
Poly = List (Nat, Mono)

public export
evalMono : List Nat -> Mono -> Nat
evalMono env [] = 1
evalMono env (i :: is) = lookupVar env i * evalMono env is

public export
evalPoly : List Nat -> Poly -> Nat
evalPoly env [] = 0
evalPoly env ((c, m) :: p) = c * evalMono env m + evalPoly env p

-- Comparisons. Only the equality needs a proof: the order only decides
-- where a monomial goes, which does not change the value of a polynomial.

public export
ltNat : Nat -> Nat -> Bool
ltNat Z (S _) = True
ltNat (S i) (S j) = ltNat i j
ltNat _ _ = False

public export
eqNat : (i, j : Nat) -> Maybe (i = j)
eqNat Z Z = Just Refl
eqNat (S i) (S j) = map (\ prf => cong S prf) (eqNat i j)
eqNat _ _ = Nothing

public export
consEq : {0 i, j : Nat} -> {0 is, js : List Nat} ->
         Maybe (i = j) -> Maybe (is = js) -> Maybe (the (List Nat) (i :: is) = j :: js)
consEq (Just Refl) (Just Refl) = Just Refl
consEq _ _ = Nothing

public export
eqMono : (m, m' : Mono) -> Maybe (m = m')
eqMono [] [] = Just Refl
eqMono (i :: is) (j :: js) = consEq (eqNat i j) (eqMono is js)
eqMono _ _ = Nothing

||| A strict total order on monomials
public export
ltMono : Mono -> Mono -> Bool
ltMono [] (_ :: _) = True
ltMono (i :: is) (j :: js)
  = if ltNat i j then True else if ltNat j i then False else ltMono is js
ltMono _ _ = False

-- Insert a variable into a monomial
mutual
  public export
  insertVar : Nat -> Mono -> Mono
  insertVar i [] = [i]
  insertVar i (j :: js) = insertVarAt i j js (ltNat j i)

  public export
  insertVarAt : Nat -> Nat -> Mono -> (jFirst : Bool) -> Mono
  insertVarAt i j js True = j :: insertVar i js
  insertVarAt i j js False = i :: j :: js

public export
mulMono : Mono -> Mono -> Mono
mulMono [] m = m
mulMono (i :: is) m = insertVar i (mulMono is m)

-- Add a monomial with its coefficient to a polynomial
mutual
  public export
  insert : (c : Nat) -> (m : Mono) -> Poly -> Poly
  insert c m [] = [(c, m)]
  insert c m ((c', m') :: p) = insertAt c m c' m' p (eqMono m m') (ltMono m m')

  public export
  insertAt : (c : Nat) -> (m : Mono) -> (c' : Nat) -> (m' : Mono) -> Poly ->
             Maybe (m = m') -> (before : Bool) -> Poly
  insertAt c m c' m' p (Just _) _ = (c + c', m') :: p
  insertAt c m c' m' p Nothing True = (c, m) :: (c', m') :: p
  insertAt c m c' m' p Nothing False = (c', m') :: insert c m p

public export
addPoly : Poly -> Poly -> Poly
addPoly [] q = q
addPoly ((c, m) :: p) q = insert c m (addPoly p q)

||| Multiply a polynomial by a monomial with its coefficient
public export
mulTerm : (c : Nat) -> (m : Mono) -> Poly -> Poly
mulTerm c m [] = []
mulTerm c m ((c', m') :: q) = insert (c * c') (mulMono m m') (mulTerm c m q)

public export
mulPoly : Poly -> Poly -> Poly
mulPoly [] q = []
mulPoly ((c, m) :: p) q = addPoly (mulTerm c m q) (mulPoly p q)

||| The normal form of an expression
public export
norm : Expr -> Poly
norm (Var i) = [(1, [i])]
norm (Lit Z) = []
norm (Lit n@(S _)) = [(n, [])]
norm (Plus a b) = addPoly (norm a) (norm b)
norm (Mult a b) = mulPoly (norm a) (norm b)

------------------------------------------------------------------------------
-- Soundness

plusSwap : (a, b, c : Nat) -> a + (b + c) = b + (a + c)
plusSwap a b c = Calc $
  |~ a + (b + c)
  ~~ (a + b) + c ...(plusAssociative a b c)
  ~~ (b + a) + c ...(cong (+ c) (plusCommutative a b))
  ~~ b + (a + c) ..<(plusAssociative b a c)

multSwap : (a, b, c : Nat) -> a * (b * c) = b * (a * c)
multSwap a b c = Calc $
  |~ a * (b * c)
  ~~ (a * b) * c ...(multAssociative a b c)
  ~~ (b * a) * c ...(cong (* c) (multCommutative a b))
  ~~ b * (a * c) ..<(multAssociative b a c)

multInterchange : (a, b, c, d : Nat) -> (a * b) * (c * d) = (a * c) * (b * d)
multInterchange a b c d = Calc $
  |~ (a * b) * (c * d)
  ~~ a * (b * (c * d)) ..<(multAssociative a b (c * d))
  ~~ a * (c * (b * d)) ...(cong (a *) (multSwap b c d))
  ~~ (a * c) * (b * d) ...(multAssociative a c (b * d))

mutual
  insertVarSound : (env : List Nat) -> (i : Nat) -> (m : Mono) ->
                   evalMono env (insertVar i m) = lookupVar env i * evalMono env m
  insertVarSound env i [] = Refl
  insertVarSound env i (j :: js) = insertVarAtSound env i j js (ltNat j i)

  insertVarAtSound : (env : List Nat) -> (i, j : Nat) -> (js : Mono) -> (b : Bool) ->
                     evalMono env (insertVarAt i j js b)
                       = lookupVar env i * (lookupVar env j * evalMono env js)
  insertVarAtSound env i j js False = Refl
  insertVarAtSound env i j js True = Calc $
    |~ lookupVar env j * evalMono env (insertVar i js)
    ~~ lookupVar env j * (lookupVar env i * evalMono env js)
         ...(cong (lookupVar env j *) (insertVarSound env i js))
    ~~ lookupVar env i * (lookupVar env j * evalMono env js)
         ...(multSwap _ _ _)

mulMonoSound : (env : List Nat) -> (m, m' : Mono) ->
               evalMono env (mulMono m m') = evalMono env m * evalMono env m'
mulMonoSound env [] m' = sym (multOneLeftNeutral _)
mulMonoSound env (i :: is) m' = Calc $
  |~ evalMono env (insertVar i (mulMono is m'))
  ~~ lookupVar env i * evalMono env (mulMono is m') ...(insertVarSound env i _)
  ~~ lookupVar env i * (evalMono env is * evalMono env m')
       ...(cong (lookupVar env i *) (mulMonoSound env is m'))
  ~~ (lookupVar env i * evalMono env is) * evalMono env m' ...(multAssociative _ _ _)

mutual
  insertSound : (env : List Nat) -> (c : Nat) -> (m : Mono) -> (p : Poly) ->
                evalPoly env (insert c m p) = c * evalMono env m + evalPoly env p
  insertSound env c m [] = Refl
  insertSound env c m ((c', m') :: p)
    = insertAtSound env c m c' m' p (eqMono m m') (ltMono m m')

  insertAtSound : (env : List Nat) -> (c : Nat) -> (m : Mono) -> (c' : Nat) ->
                  (m' : Mono) -> (p : Poly) -> (eq : Maybe (m = m')) -> (b : Bool) ->
                  evalPoly env (insertAt c m c' m' p eq b)
                    = c * evalMono env m + (c' * evalMono env m' + evalPoly env p)
  insertAtSound env c m c' m p (Just Refl) b = Calc $
    |~ (c + c') * evalMono env m + evalPoly env p
    ~~ (c * evalMono env m + c' * evalMono env m) + evalPoly env p
         ...(cong (+ evalPoly env p) (multDistributesOverPlusLeft c c' _))
    ~~ c * evalMono env m + (c' * evalMono env m + evalPoly env p)
         ..<(plusAssociative _ _ _)
  insertAtSound env c m c' m' p Nothing True = Refl
  insertAtSound env c m c' m' p Nothing False = Calc $
    |~ c' * evalMono env m' + evalPoly env (insert c m p)
    ~~ c' * evalMono env m' + (c * evalMono env m + evalPoly env p)
         ...(cong (c' * evalMono env m' +) (insertSound env c m p))
    ~~ c * evalMono env m + (c' * evalMono env m' + evalPoly env p)
         ...(plusSwap _ _ _)

addPolySound : (env : List Nat) -> (p, q : Poly) ->
               evalPoly env (addPoly p q) = evalPoly env p + evalPoly env q
addPolySound env [] q = Refl
addPolySound env ((c, m) :: p) q = Calc $
  |~ evalPoly env (insert c m (addPoly p q))
  ~~ c * evalMono env m + evalPoly env (addPoly p q) ...(insertSound env c m _)
  ~~ c * evalMono env m + (evalPoly env p + evalPoly env q)
       ...(cong (c * evalMono env m +) (addPolySound env p q))
  ~~ (c * evalMono env m + evalPoly env p) + evalPoly env q ...(plusAssociative _ _ _)

mulTermSound : (env : List Nat) -> (c : Nat) -> (m : Mono) -> (q : Poly) ->
               evalPoly env (mulTerm c m q) = (c * evalMono env m) * evalPoly env q
mulTermSound env c m [] = sym (multZeroRightZero _)
mulTermSound env c m ((c', m') :: q) = Calc $
  |~ evalPoly env (insert (c * c') (mulMono m m') (mulTerm c m q))
  ~~ (c * c') * evalMono env (mulMono m m') + evalPoly env (mulTerm c m q)
       ...(insertSound env _ _ _)
  ~~ (c * c') * (evalMono env m * evalMono env m') + evalPoly env (mulTerm c m q)
       ...(cong (\ v => (c * c') * v + evalPoly env (mulTerm c m q)) (mulMonoSound env m m'))
  ~~ (c * evalMono env m) * (c' * evalMono env m') + evalPoly env (mulTerm c m q)
       ...(cong (+ evalPoly env (mulTerm c m q)) (multInterchange _ _ _ _))
  ~~ (c * evalMono env m) * (c' * evalMono env m') + (c * evalMono env m) * evalPoly env q
       ...(cong ((c * evalMono env m) * (c' * evalMono env m') +) (mulTermSound env c m q))
  ~~ (c * evalMono env m) * (c' * evalMono env m' + evalPoly env q)
       ..<(multDistributesOverPlusRight _ _ _)

mulPolySound : (env : List Nat) -> (p, q : Poly) ->
               evalPoly env (mulPoly p q) = evalPoly env p * evalPoly env q
mulPolySound env [] q = Refl
mulPolySound env ((c, m) :: p) q = Calc $
  |~ evalPoly env (addPoly (mulTerm c m q) (mulPoly p q))
  ~~ evalPoly env (mulTerm c m q) + evalPoly env (mulPoly p q) ...(addPolySound env _ _)
  ~~ (c * evalMono env m) * evalPoly env q + evalPoly env (mulPoly p q)
       ...(cong (+ evalPoly env (mulPoly p q)) (mulTermSound env c m q))
  ~~ (c * evalMono env m) * evalPoly env q + evalPoly env p * evalPoly env q
       ...(cong ((c * evalMono env m) * evalPoly env q +) (mulPolySound env p q))
  ~~ (c * evalMono env m + evalPoly env p) * evalPoly env q
       ..<(multDistributesOverPlusLeft _ _ _)

||| The normal form of an expression has the value of the expression
export
normSound : (env : List Nat) -> (e : Expr) -> evalPoly env (norm e) = eval env e
normSound env (Var i) = Calc $
  |~ 1 * (lookupVar env i * 1) + 0
  ~~ 1 * (lookupVar env i * 1) ...(plusZeroRightNeutral _)
  ~~ lookupVar env i * 1 ...(multOneLeftNeutral _)
  ~~ lookupVar env i ...(multOneRightNeutral _)
normSound env (Lit Z) = Refl
normSound env (Lit (S k)) = Calc $
  |~ S k * 1 + 0
  ~~ S k * 1 ...(plusZeroRightNeutral _)
  ~~ S k ...(multOneRightNeutral _)
normSound env (Plus a b) = Calc $
  |~ evalPoly env (addPoly (norm a) (norm b))
  ~~ evalPoly env (norm a) + evalPoly env (norm b) ...(addPolySound env _ _)
  ~~ eval env a + eval env b ...(cong2 (+) (normSound env a) (normSound env b))
normSound env (Mult a b) = Calc $
  |~ evalPoly env (mulPoly (norm a) (norm b))
  ~~ evalPoly env (norm a) * evalPoly env (norm b) ...(mulPolySound env _ _)
  ~~ eval env a * eval env b ...(cong2 (*) (normSound env a) (normSound env b))

||| Two expressions with the same normal form are equal
export
prove : (env : List Nat) -> (lhs, rhs : Expr) -> norm lhs = norm rhs ->
        eval env lhs = eval env rhs
prove env lhs rhs prf = Calc $
  |~ eval env lhs
  ~~ evalPoly env (norm lhs) ..<(normSound env lhs)
  ~~ evalPoly env (norm rhs) ...(cong (evalPoly env) prf)
  ~~ eval env rhs ...(normSound env rhs)

------------------------------------------------------------------------------
-- Reflection
--
-- The functions below run in the module which uses the solver: they may only
-- use the Prelude and the modules imported publicly here.

||| The index of an atom in the list of atoms seen so far, which grows if it
||| is new. Atoms are compared syntactically, without their locations.
public export
atomIndex : List TTImp -> TTImp -> (List TTImp, Nat)
atomIndex atoms t = go 0 atoms
  where
    go : Nat -> List TTImp -> (List TTImp, Nat)
    go i [] = ([t], i)
    go i (a :: as) = if a == t then (a :: as, i)
                       else let (as', j) = go (S i) as in (a :: as', j)

mutual
  ||| Reify a normalised term of type `Nat`, given the atoms seen so far. After
  ||| normalisation, `+` and `*` (of `Num Nat`) are `plus` and `mult`, and a
  ||| literal is a chain of `S`.
  public export
  reify : List TTImp -> TTImp -> (List TTImp, Expr)
  reify atoms t@(IVar _ n)
    = if n == `{Prelude.Types.Z} then (atoms, Lit 0) else atom atoms t
  reify atoms t@(IApp _ (IVar _ s) x)
    = if s == `{Prelude.Types.S} then succs 1 atoms x else atom atoms t
  reify atoms t@(IApp _ (IApp _ (IVar _ f) a) b)
    = if f == `{Prelude.Types.plus} then binary Plus atoms a b
      else if f == `{Prelude.Types.mult} then binary Mult atoms a b
      else atom atoms t
  reify atoms t = atom atoms t

  -- k applications of S to the term
  succs : (k : Nat) -> List TTImp -> TTImp -> (List TTImp, Expr)
  succs k atoms t@(IApp _ (IVar _ s) x)
    = if s == `{Prelude.Types.S} then succs (S k) atoms x
        else let (atoms, e) = reify atoms t in (atoms, Plus (Lit k) e)
  succs k atoms t@(IVar _ n)
    = if n == `{Prelude.Types.Z} then (atoms, Lit k)
        else let (atoms, e) = reify atoms t in (atoms, Plus (Lit k) e)
  succs k atoms t = let (atoms, e) = reify atoms t in (atoms, Plus (Lit k) e)

  binary : (Expr -> Expr -> Expr) -> List TTImp -> TTImp -> TTImp -> (List TTImp, Expr)
  binary op atoms a b = let (atoms, ea) = reify atoms a
                            (atoms, eb) = reify atoms b in
                        (atoms, op ea eb)

  atom : List TTImp -> TTImp -> (List TTImp, Expr)
  atom atoms t = let (atoms, i) = atomIndex atoms t in (atoms, Var i)

||| The two sides of a normalised goal `lhs = rhs` at type `Nat`
public export
natEquality : TTImp -> Maybe (TTImp, TTImp)
natEquality t = case appView t of
  Just (MkAppView (_, eq) [<NamedArg _ _ ta, NamedArg _ _ tb, Arg _ l, Arg _ r] _) =>
    if eq == `{Builtin.Equal} && isNat ta && isNat tb then Just (l, r) else Nothing
  _ => Nothing
  where
    isNat : TTImp -> Bool
    isNat (IVar _ n) = n == `{Prelude.Types.Nat}
    isNat _ = False

natTTImp : Nat -> TTImp
natTTImp n = IApp EmptyFC (IVar EmptyFC `{Prelude.Num.fromInteger})
                          (IPrimVal EmptyFC (BI (natToInteger n)))

||| An expression as syntax
public export
exprTTImp : Expr -> TTImp
exprTTImp (Var i) = IApp EmptyFC (IVar EmptyFC `{Data.Nat.Solver.Var}) (natTTImp i)
exprTTImp (Lit n) = IApp EmptyFC (IVar EmptyFC `{Data.Nat.Solver.Lit}) (natTTImp n)
exprTTImp (Plus a b)
  = IApp EmptyFC (IApp EmptyFC (IVar EmptyFC `{Data.Nat.Solver.Plus}) (exprTTImp a)) (exprTTImp b)
exprTTImp (Mult a b)
  = IApp EmptyFC (IApp EmptyFC (IVar EmptyFC `{Data.Nat.Solver.Mult}) (exprTTImp a)) (exprTTImp b)

listTTImp : List TTImp -> TTImp
listTTImp [] = IVar EmptyFC `{Prelude.Basics.Nil}
listTTImp (t :: ts)
  = IApp EmptyFC (IApp EmptyFC (IVar EmptyFC `{Prelude.Basics.(::)}) t) (listTTImp ts)

||| A polynomial, with the given names for its atoms
public export
showPoly : List String -> Poly -> String
showPoly names [] = "0"
showPoly names (t :: ts) = term t ++ concatMap ((" + " ++) . term) ts
  where
    name : Nat -> String
    name i = case drop i names of
               (n :: _) => n
               [] => "?"

    vars : Mono -> String
    vars [] = "1"
    vars (i :: is) = name i ++ concatMap ((" * " ++) . name) is

    term : (Nat, Mono) -> String
    term (c, []) = show c
    term (1, m) = vars m
    term (c, m) = show c ++ " * " ++ vars m

||| Prove an equality of natural numbers which holds in every commutative
||| semiring: the two sides are normalised (unfolding the definitions which
||| are visible here, so that `+` and `*` become `plus` and `mult`), reified
||| as polynomials over their atoms, and compared.
export %macro
solveNat : Elab a
solveNat = do
  Just g <- goal
    | Nothing => fail "solveNat: the goal is not known"
  ty <- check {expected = Type} g
  ng <- quoteNF False ty
  let Just (l, r) = natEquality ng
    | Nothing => fail $ "solveNat: the goal is not an equality of natural numbers: "
                        ++ !(resugarTerm Nothing g)
  let (atoms, el) = reify [] l
  let (atoms, er) = reify atoms r
  let nl = norm el
  let nr = norm er
  when (nl /= nr) $ do
    names <- traverse (map parens . resugarTerm Nothing) atoms
    fail $ "solveNat: the two sides are not equal as polynomials:\n  "
           ++ showPoly names nl ++ "\n  " ++ showPoly names nr
  check $ IApp EmptyFC (IApp EmptyFC (IApp EmptyFC (IApp EmptyFC
            (IVar EmptyFC `{Data.Nat.Solver.prove})
            (listTTImp atoms)) (exprTTImp el)) (exprTTImp er))
            (IVar EmptyFC `{Builtin.Refl})
  where
    parens : String -> String
    parens s = if any (== ' ') (unpack s) then "(" ++ s ++ ")" else s
