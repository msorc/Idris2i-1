||| Types declared in another module than the one that compiles the program:
||| their table comes from this module's TTC.
module Rec

public export
record Particle where
  constructor MkParticle
  px : Double
  py : Double
  hits : Int

||| A newtype of a Double: no cell, and a field of this type is a Double.
public export
record Meters where
  constructor MkMeters
  meters : Double

||| A type that reduces to Double where it is `public export` ...
public export
Real : Type
Real = Double

||| ... and one that does not reduce outside this module.
export
Opaque : Type
Opaque = Double

export
mkOpaque : Double -> Opaque
mkOpaque x = x

export
unOpaque : Opaque -> Double
unOpaque x = x

public export
data Colour = Red | Green | Blue
