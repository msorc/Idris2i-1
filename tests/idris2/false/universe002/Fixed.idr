||| Universe polymorphism must not rename what evaluation produces.
module Fixed

-- T evaluates to a Type; if each use of T could choose its own universe,
-- this would be Type : Type
T : Type
T = Type

selfT : T
selfT = T
