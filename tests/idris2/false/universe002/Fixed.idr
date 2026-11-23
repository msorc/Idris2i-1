||| A reference to a definition is a copy of it, renamed with the reference,
||| but the references within a mutual block are to one copy (as in Coq).
||| (Outside one, `x : T; x = T` is accepted: see universe009.)
module Fixed

-- T evaluates to a Type, and selfT's two uses of T are the same copy: this
-- would be Type : Type
mutual
  T : Type
  T = Type

  selfT : T
  selfT = T
