module Algebra

import public Algebra.ZeroOneOmega
import public Algebra.Semiring
import public Algebra.Preorder

%default total

public export
RigCount : Type
RigCount = ZeroOneOmega

||| A product of quantity variables as written: `%q`, or `%q*%r`
export
showVarsCount : RigCount -> Maybe String
showVarsCount r = case rigVars r of
                       [] => Nothing
                       (v :: vs) => Just (foldl (\acc, w => acc ++ "*" ++ show w) (show v) vs)

||| The same, with the owners of the variables: to tell apart variables of
||| the same name
export
showVarsCountOwned : RigCount -> Maybe String
showVarsCountOwned r
    = case rigVars r of
           [] => Nothing
           (v :: vs) => Just (foldl (\acc, w => acc ++ "*" ++ owned w) (owned v) vs)
  where
    owned : QuantityVar -> String
    owned v = show v ++ " (of " ++ qvOwner v ++ ")"

||| Do the two quantities have different variables of the same name?
export
clashingVars : RigCount -> RigCount -> Bool
clashingVars r s
    = any (\v => any (\w => qvName v == qvName w && qvOwner v /= qvOwner w) (rigVars s))
          (rigVars r)

export
showCount : RigCount -> String
showCount = elimSemi "0 " "1 " (\r => maybe "" (++ " ") (showVarsCount r))
