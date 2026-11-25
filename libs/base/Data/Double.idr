||| Various IEEE floating-point number constants
module Data.Double

||| Largest number that can be added to a floating-point number without changing
||| its value, i.e. `1.0 + unitRoundoff == 1.0`.
%foreign "scheme:blodwen-calcFlonumUnitRoundoff"
         "RefC:idris2i_1_flonumUnitRoundoff"
         "node:lambda:()=>Number.EPSILON / 2"
export
unitRoundoff : Double

||| Machine epsilon is the smallest floating-point number that distinguishes two
||| floating-point numbers; the step size on the floating-point number line.
%foreign "scheme:blodwen-calcFlonumEpsilon"
         "RefC:idris2i_1_flonumEpsilon"
         "node:lambda:()=>Number.EPSILON"
export
epsilon : Double


||| Not a number, e.g. `0.0 / 0.0`. Never equal to anything, including itself.
%foreign "scheme:blodwen-flonumNaN"
         "RefC:idris2i_1_flonumNaN"
         "node:lambda:()=>Number.NaN"
export
nan : Double


||| Positive Infinity. Can be negated to obtain Negative Infinity.
%foreign "scheme:blodwen-flonumInf"
         "RefC:idris2i_1_flonumInf"
         "node:lambda:()=>Infinity"
export
inf : Double

