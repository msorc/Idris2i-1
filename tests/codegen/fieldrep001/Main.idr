||| The field representation table (see Core.FieldRep) of a set of types
||| that are tricky for it.  The run prints the tables of the constructors,
||| as --dumpcases and --dump-anf show them, and runs the program, whose
||| output must not depend on them.
module Main

import Rec
import Data.Vect
import Control.Monad.Identity

-- Type variables are boxed, the fixed width primitive types are not.
data Box a = MkBox a Double Int String Integer Nat

-- All the fixed width primitive types.
data Prims = MkPrims Int Int8 Int16 Int32 Int64 Bits8 Bits16 Bits32 Bits64 Char Double

-- An indexed family: the index is erased.
data V : Nat -> Type where
  VNil : V Z
  VCons : Double -> V n -> V (S n)

-- A dependent record: the second field's type depends on the first.
record Dep where
  constructor MkDep
  isInt : Bool
  val : if isInt then Int else Double

-- Erased and linear fields.
data EL : Type where
  MkEL : (0 n : Nat) -> (1 d : Double) -> Int -> EL

-- Enumerations, and a newtype of a Double from another module.
record Pixel where
  constructor MkPixel
  colour : Colour
  visible : Bool
  scale : Meters

-- A newtype whose field is a type variable: boxed even at Double.
data UsesIdentity = MkUI (Identity Double)

-- Type synonyms: one reduces here, one does not.
data Aliases = MkAliases Real Opaque

-- Lazy, Inf and functions.
data Delayed = MkDelayed (Lazy Double) (Inf Int) (Int -> Double)

-- Mutual and nested types.
mutual
  data Tree = Node Double Forest
  data Forest = None | Trees Tree Forest

-- In a mutual block, an enumeration declared after its use is not known to
-- be one yet: the table is the one computed then, in every module.
mutual
  data UsesLater = MkUsesLater Later Double
  data Later = L1 | L2

data UsesEarlier = MkUsesEarlier Later Double

data Nested = MkNested (Maybe Double) (Double, Int) (Vect 2 Double) Particle

-- A two-field record is "cons shaped": its uses are compiled as the
-- intrinsic _builtin.CONS, whose fields are boxed.
record V2 where
  constructor MkV2
  x : Double
  y : Double

-- A record that is not a newtype by request.
data Wrapped : Type where [noNewtype]
  MkWrapped : Double -> Wrapped

-- An interface: its dictionary holds functions.
interface Norm a where
  constructor MkNorm
  norm : a -> Double

Norm V2 where
  norm v = sqrt (v.x * v.x + v.y * v.y)

sumV : V n -> Double
sumV VNil = 0.0
sumV (VCons d rest) = d + sumV rest

depVal : Dep -> Double
depVal (MkDep True v) = cast v
depVal (MkDep False v) = v

treeSum : Tree -> Double
treeSum (Node d f) = d + forestSum f
  where
    forestSum : Forest -> Double
    forestSum None = 0.0
    forestSum (Trees t rest) = treeSum t + forestSum rest

main : IO ()
main = do
  let b = MkBox "a" 1.5 2 "s" 3 4
  let MkBox _ d i _ _ _ = b
  let p = MkPixel Blue True (MkMeters 2.5)
  let MkAliases r o = MkAliases 1.0 (mkOpaque 2.0)
  let MkEL _ e k = MkEL 3 0.5 7
  let MkNested _ _ _ q = MkNested Nothing (1.0, 2) [1.0, 2.0] (MkParticle 1.0 2.0 3)
  let MkDelayed l _ f = MkDelayed 4.0 5 cast
  let MkWrapped w = MkWrapped 0.25
  printLn $ the (List Double) [ d + cast i, sumV (VCons 1.0 (VCons 2.0 VNil))
          , depVal (MkDep True 3), depVal (MkDep False 0.5)
          , treeSum (Node 1.0 (Trees (Node 2.0 None) None))
          , norm (MkV2 3.0 4.0), p.scale.meters, r + unOpaque o, e + cast k
          , q.px + q.py + cast q.hits, l + f 1, w ]
  printLn (p.visible, case p.colour of Blue => "blue"; _ => "other")
