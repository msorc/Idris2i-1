module Geometry.Shape

public export
data Shape = Circle Nat | Rect Nat Nat | Tri Nat Nat

export
area : Shape -> Nat
area (Circle r) = 3 * r * r
area (Rect w h) = w * h
area (Tri b h) = b * h + 1

export
name : Shape -> String
name (Circle _) = "circle"
name (Rect _ _) = "rectangle"
name (Tri _ _) = "triangle"
