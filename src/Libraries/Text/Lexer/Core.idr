module Libraries.Text.Lexer.Core

import Data.List
import Data.Maybe

import public Libraries.Control.Delayed
import public Libraries.Text.Bounded

%default total

||| A language of token recognisers.
||| @ consumes If `True`, this recogniser is guaranteed to consume at
|||            least one character of input when it succeeds.
export
data Recognise : (consumes : Bool) -> Type where
     Empty : Recognise False
     Fail : Recognise c
     EOF : Recognise False
     Lookahead : (positive : Bool) -> Recognise c -> Recognise False
     Pred : (Char -> Bool) -> Recognise True
     SeqEat : Recognise True -> Inf (Recognise e) -> Recognise True
     SeqEmpty : Recognise e1 -> Recognise e2 -> Recognise (e1 || e2)
     SeqSame : Recognise e -> Recognise e -> Recognise e
     Alt : Recognise e1 -> Recognise e2 -> Recognise (e1 && e2)
     -- The longest run of characters that satisfy the predicate (what
     -- `many (pred f)` recognises, one character at a time)
     PredMany : (Char -> Bool) -> Recognise False

||| A token recogniser. Guaranteed to consume at least one character.
public export
Lexer : Type
Lexer = Recognise True

||| Sequence two recognisers. If either consumes a character, the sequence
||| is guaranteed to consume a character.
export %inline
(<+>) : {c1 : Bool} ->
        Recognise c1 -> inf c1 (Recognise c2) -> Recognise (c1 || c2)
(<+>) {c1 = False} = SeqEmpty
(<+>) {c1 = True} = SeqEat

||| Alternative recognisers. If both consume, the combination is guaranteed
||| to consume a character.
export %inline
(<|>) : Recognise c1 -> Recognise c2 -> Recognise (c1 && c2)
(<|>) = Alt

||| A recogniser that always fails.
export %inline
fail : Recognise c
fail = Fail

||| Recognise no input (doesn't consume any input)
export %inline
empty : Recognise False
empty = Empty

||| Recognise end of input
export %inline
eof : Recognise False
eof = EOF

||| Recognise a character that matches a predicate
export %inline
pred : (Char -> Bool) -> Lexer
pred = Pred

||| Positive lookahead. Never consumes input.
export %inline
expect : Recognise c -> Recognise False
expect = Lookahead True

||| Negative lookahead. Never consumes input.
export %inline
reject : Recognise c -> Recognise False
reject = Lookahead False

||| Recognise the longest run of characters (maybe none) that satisfy a
||| predicate: the same as `many (pred f)`, without making the recogniser of
||| the rest of the run at each character.
export %inline
predMany : (Char -> Bool) -> Recognise False
predMany = PredMany

||| The predicate of a recogniser of one character, if it is one
export
isPred : Recognise c -> Maybe (Char -> Bool)
isPred (Pred f) = Just f
isPred _ = Nothing

||| Sequence the recognisers resulting from applying a function to each element
||| of a list. The resulting recogniser will consume input if the produced
||| recognisers consume and the list is non-empty.
export
concatMap : (a -> Recognise c) -> (xs : List a) -> Recognise (isCons xs && c)
concatMap _ []                 = Empty
concatMap f (x :: [])          = f x
concatMap f (x :: xs@(_ :: _)) = SeqSame (f x) (concatMap f xs)

data StrLen : Type where
     MkStrLen : String -> Nat -> StrLen

getString : StrLen -> String
getString (MkStrLen str n) = str

strIndex : StrLen -> Nat -> Maybe Char
strIndex (MkStrLen str len) i
    = if cast {to = Integer} i >= cast len then Nothing
      else Just (assert_total (prim__strIndex str (cast i)))

mkStr : String -> StrLen
mkStr str = MkStrLen str (length str)

strTail : Nat -> StrLen -> StrLen
strTail start (MkStrLen str len)
    = MkStrLen (substr start len str) (minus len start)

-- If the string is recognised, returns the index at which the token
-- ends
-- (written with `case` rather than in the `Maybe` monad: a bind makes a
-- closure for its continuation, at each step of each recogniser)
export
scan : Recognise c -> SnocList Char -> List Char -> Maybe (SnocList Char, List Char)
scan Empty tok str = Just (tok, str)
scan Fail tok str = Nothing
scan EOF tok [] = Just (tok,[])
scan EOF tok (_::_) = Nothing
scan (Lookahead positive r) tok str
    = if isJust (scan r tok str) == positive
         then Just (tok, str)
         else Nothing
scan (Pred f) tok [] = Nothing
scan (Pred f) tok (c :: str)
    = if f c
         then Just (tok :< c, str)
         else Nothing
scan (SeqEat r1 r2) tok str
    = case scan r1 tok str of
        Nothing => Nothing
        -- TODO: Can we prove totality instead by showing idx has increased?
        Just (tok', rest) => assert_total (scan r2 tok' rest)
scan (SeqEmpty r1 r2) tok str
    = case scan r1 tok str of
        Nothing => Nothing
        Just (tok', rest) => scan r2 tok' rest
scan (SeqSame r1 r2) tok str
    = case scan r1 tok str of
        Nothing => Nothing
        Just (tok', rest) => scan r2 tok' rest
scan (Alt r1 r2) tok str
    = case scan r1 tok str of
        Nothing => scan r2 tok str
        res => res
scan (PredMany f) tok str = Just (spanPred tok str)
  where
    spanPred : SnocList Char -> List Char -> (SnocList Char, List Char)
    spanPred tok [] = (tok, [])
    spanPred tok (c :: cs) = if f c then spanPred (tok :< c) cs else (tok, c :: cs)

-- Whether a recogniser can succeed on an input that starts with the given
-- character, by consuming it (first) or without consuming anything
-- (second). The answers err on the side of `True`: when one is `False`,
-- `scan` cannot succeed that way. The rest of a `SeqEat` is only looked at
-- when its first part can succeed without consuming anything, which it
-- cannot (it consumes, by its type), so the recursive recognisers, whose
-- recursive calls are under a `SeqEat`, are never unfolded.
startsWith : Recognise c -> Char -> (Bool, Bool)
startsWith Empty c = (False, True)
startsWith Fail c = (False, False)
startsWith EOF c = (False, False) -- the input is not empty
startsWith (Lookahead _ _) c = (False, True)
startsWith (Pred f) c = (f c, False)
startsWith (SeqEat r1 r2) c
    = let (eat1, empty1) = startsWith r1 c in
          (eat1 || (empty1 && fst (startsWith (assert_smaller r1 r2) c)),
           empty1 && snd (startsWith (assert_smaller r1 r2) c))
startsWith (SeqEmpty r1 r2) c
    = let (eat1, empty1) = startsWith r1 c in
          (eat1 || (empty1 && fst (startsWith r2 c)),
           empty1 && snd (startsWith r2 c))
startsWith (SeqSame r1 r2) c
    = let (eat1, empty1) = startsWith r1 c in
          (eat1 || (empty1 && fst (startsWith r2 c)),
           empty1 && snd (startsWith r2 c))
startsWith (Alt r1 r2) c
    = let (eat1, empty1) = startsWith r1 c
          (eat2, empty2) = startsWith r2 c in
          (eat1 || eat2, empty1 || empty2)
startsWith (PredMany f) c = (f c, True)

||| Whether a recogniser may succeed on an input that starts with the given
||| character. When this is `False`, `scan` fails on every such input; when it
||| is `True`, it may fail too.
export
mayStartWith : Recognise c -> Char -> Bool
mayStartWith r c = let (eat, empty) = startsWith r c in eat || empty

-- we don't actually care about the list, so may as well just return the Nat
locate : (a -> Bool) -> SnocList a -> (SnocList a, Nat)
locate p sx = go sx Z where

  go : SnocList a -> Nat -> (SnocList a, Nat)
  go [<] xs = ([<], xs)
  go sxx@(sx :< x) xs = if p x then (sxx, xs) else go sx (S xs)

||| A mapping from lexers to the tokens they produce.
||| This is a list of pairs `(Lexer, String -> tokenType)`
||| For each Lexer in the list, if a substring in the input matches, run
||| the associated function to produce a token of type `tokenType`
public export
TokenMap : (tokenType : Type) -> Type
TokenMap tokenType = List (Lexer, String -> tokenType)

export
countNLs : SnocList Char -> Nat
countNLs str = SnocList.length (filter (== '\n') str)

export
getCols : SnocList Char -> Int -> Int
getCols x c
  = case locate (== '\n') x of
      ([<], incol) => c + cast incol
      (_, incol) => cast incol

||| The line and column after a token, given those of its start: the
||| result of `countNLs` and `getCols`, in one pass over the token.
export
advance : SnocList Char -> (line, col : Int) -> (Int, Int)
advance tok line col = inLine tok 0
  where
    newlines : SnocList Char -> Int -> Int
    newlines [<] n = n
    newlines (sx :< '\n') n = newlines sx (n + 1)
    newlines (sx :< _) n = newlines sx n

    -- the characters after the last newline
    inLine : SnocList Char -> Int -> (Int, Int)
    inLine [<] n = (line, col + n)
    inLine (sx :< '\n') n = (newlines sx (line + 1), n)
    inLine (sx :< _) n = inLine sx (n + 1)

tokenise : (a -> Bool) ->
           (line : Int) -> (col : Int) ->
           SnocList (WithBounds a) -> TokenMap a ->
           List Char -> (List (WithBounds a), (Int, Int, List Char))
tokenise pred line col acc tmap str
    = case getFirstToken tmap str of
           Just (tok, line', col', rest) =>
           -- assert total because getFirstToken must consume something
               if pred tok.val
                  then (acc <>> [], (line, col, []))
                  else assert_total (tokenise pred line' col' (acc :< tok) tmap rest)
           Nothing => (acc <>> [], (line, col, str))
  where

    getFirstToken : TokenMap a -> List Char ->
                    Maybe (WithBounds a, Int, Int, List Char)
    getFirstToken [] str = Nothing
    getFirstToken ((lex, fn) :: ts) str
        = case scan lex [<] str of
               Just (tok, rest) =>
                 let (line', col') = advance tok line col in
                     Just (MkBounded (fn (fastPack (tok <>> []))) False (MkBounds line col line' col'),
                           line', col', rest)
               Nothing => getFirstToken ts str

export
lexTo : (a -> Bool) ->
        TokenMap a -> String -> (List (WithBounds a), (Int, Int, String))
lexTo pred tmap str
    = let (ts, (l, c, str')) = tokenise pred 0 0 [<] tmap (fastUnpack str) in
          (ts, (l, c, fastPack str'))

||| Given a mapping from lexers to token generating functions (the
||| TokenMap a) and an input string, return a list of recognised tokens,
||| and the line, column, and remainder of the input at the first point in the
||| string where there are no recognised tokens.
export %inline
lex : TokenMap a -> String -> (List (WithBounds a), (Int, Int, String))
lex = lexTo (const False)
