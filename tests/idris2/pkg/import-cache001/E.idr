module E

-- checked after D in the same process: what D hides is visible here again,
-- and D's own (private) definitions are not
import B
import D

public export
e : Nat
e = g +++ d

public export
eDescr : String
eDescr = describe (MkT e)
