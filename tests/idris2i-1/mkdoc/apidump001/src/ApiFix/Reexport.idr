||| Re-exports
module ApiFix.Reexport

import public ApiFix.Basic
import public ApiFix.Shapes as S
import Data.List

export
area : Shape -> Double
area (Circle r) = 3 * r * r
area (Rect w h) = w * h
