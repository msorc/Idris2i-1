||| The shape of `join` in `Text.Parser.Core` (contrib, and the compiler's
||| copy): `SeqEmpty` hides the intermediate type `a` in a field, and `join`
||| instantiates it at a grammar of the same copy (the identity function
||| makes the inner grammar the result's), so the grammar would hold itself.
||| Not typeable predicatively.
module GrammarJoin

%default total

data Grammar : Type -> Type where
  Empty : a -> Grammar a
  SeqEmpty : Grammar a -> (a -> Grammar b) -> Grammar b

join : Grammar (Grammar a) -> Grammar a
join p = SeqEmpty p (\ g => g)
