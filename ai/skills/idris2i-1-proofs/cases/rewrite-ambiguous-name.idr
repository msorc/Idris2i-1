-- expect: E1002
import Data.List

%default total

-- Data.List has a lemma with this name and type, so the rewrite rule is ambiguous.
appendNilRightNeutral : (xs : List a) -> xs ++ [] = xs
appendNilRightNeutral [] = Refl
appendNilRightNeutral (x :: xs) = rewrite appendNilRightNeutral xs in Refl
