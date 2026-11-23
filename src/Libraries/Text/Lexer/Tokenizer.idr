module Libraries.Text.Lexer.Tokenizer

import Data.List
import Data.Nat

import Libraries.Text.Lexer.Core
import Libraries.Text.PrettyPrint.Prettyprinter

import public Libraries.Control.Delayed
import public Libraries.Text.Bounded

%default total

||| A table indexed by the ASCII characters: a binary search tree on their
||| codes, whose leaves are the runs of characters that map to the same
||| entry.
data CharTable : Type -> Type where
     Leaf : a -> CharTable a
     -- the codes below the bound go left
     Node : (bound : Int) -> CharTable a -> CharTable a -> CharTable a

lookupTable : Int -> CharTable a -> a
lookupTable c (Leaf x) = x
lookupTable c (Node bound l r) = if c < bound then lookupTable c l else lookupTable c r

||| Description of a language's tokenization rule.
export
data Tokenizer : (tokenType : Type) -> Type where
     Match : Lexer -> (String -> tokenType) -> Tokenizer tokenType
     Compose : (begin : Lexer) ->
               (mapBegin : String -> tokenType) ->
               (tagger : String -> tag) ->
               (middle : Inf (tag -> Tokenizer tokenType)) ->
               (end : tag -> Lexer) ->
               (mapEnd : String -> tokenType) ->
               Tokenizer tokenType
     -- (strict: a lazy rule would be made again each time that it is tried,
     -- for each token, as lazy values are not shared)
     Alt : Tokenizer tokenType -> Tokenizer tokenType -> Tokenizer tokenType
     -- Alternatives chosen by the first character of the input (see
     -- `dispatch`): for an ASCII character, those of the list that can start
     -- with it, in the table; for any other character, all of them.
     Dispatch : CharTable (List (Tokenizer tokenType)) ->
                List (Tokenizer tokenType) -> Tokenizer tokenType

||| Alternative tokenizer rules.
export %inline
(<|>) : Tokenizer t -> Tokenizer t -> Tokenizer t
(<|>) = Alt

||| Match on a recogniser and cast the string to a token.
export %inline
match : Lexer -> (String -> a) -> Tokenizer a
match = Match

||| Compose other tokenizer. Language composition should be quoted between
||| a begin lexer and a end lexer. The begin token can be used to generate
||| the composition tokenizer and the end lexer.
export %inline
compose : (begin : Lexer) ->
          (mapBegin : String -> a) ->
          (tagger : String -> tag) ->
          (middle : Inf (tag -> Tokenizer a)) ->
          (end : tag -> Lexer) ->
          (mapEnd : String -> a) ->
          Tokenizer a
compose = Compose

-- The alternatives of a tokenizer, in order
alternatives : Tokenizer a -> List (Tokenizer a)
alternatives (Alt t1 t2) = alternatives t1 ++ alternatives t2
alternatives t = [t]

-- Whether the rule may apply to an input that starts with the character
mayStart : Tokenizer a -> Char -> Bool
mayStart (Match lex _) c = mayStartWith lex c
mayStart (Compose begin _ _ _ _ _) c = mayStartWith begin c
mayStart (Alt t1 t2) c = mayStart t1 c || mayStart t2 c
mayStart (Dispatch _ ts) c = any (\t => mayStart (assert_smaller ts t) c) ts

||| The same tokenizer, which only tries, for each token, the alternatives
||| that can start with its first character: those that can't would fail,
||| so the result is the same. Worth it for a tokenizer with many
||| alternatives that is used for a whole input, as the table is computed
||| here, once.
export
dispatch : Tokenizer a -> Tokenizer a
dispatch t
    = let alts = alternatives t
          numbered = zip [0 .. length alts] alts in
          Dispatch (build (runs numbered 1 0 (entry numbered 0) [<])) alts
  where
    -- the numbers of the alternatives that may start with the character
    entry : List (Nat, Tokenizer a) -> Int -> List Nat
    entry numbered c = map fst (filter (\nt => mayStart (snd nt) (chr c)) numbered)

    select : List (Nat, Tokenizer a) -> List Nat -> List (Tokenizer a)
    select numbered ns = map snd (filter (\nt => fst nt `elem` ns) numbered)

    -- the runs of consecutive ASCII codes with the same alternatives: their
    -- first code and their alternatives
    runs : List (Nat, Tokenizer a) -> (code, start : Int) -> List Nat ->
           SnocList (Int, List (Tokenizer a)) -> List (Int, List (Tokenizer a))
    runs numbered code start cur acc
        = if code >= 128
             then acc <>> [(start, select numbered cur)]
             else let next = entry numbered code in
                      if next == cur
                         then assert_total (runs numbered (code + 1) start cur acc)
                         else assert_total
                                (runs numbered (code + 1) code next
                                      (acc :< (start, select numbered cur)))

    build : List (Int, List (Tokenizer a)) -> CharTable (List (Tokenizer a))
    build [] = Leaf []
    build [(_, x)] = Leaf x
    build xs = let (l, r) = splitAt (divNatNZ (length xs) 2 SIsNonZero) xs in
                   case r of
                     ((bound, _) :: _) =>
                       Node bound (assert_total (build l)) (assert_total (build r))
                     [] => assert_total (build l)

||| Stop reason why tokenizer can't make more progress.
||| @ ComposeNotClosing carries the span of composition begin token in the
|||                     form of `(startLine, startCol), (endLine, endCol)`.
public export
data StopReason = EndInput | NoRuleApply | ComposeNotClosing (Int, Int) (Int, Int)

export
Show StopReason where
  show EndInput = "EndInput"
  show NoRuleApply = "NoRuleApply"
  show (ComposeNotClosing start end) = "ComposeNotClosing " ++ show start ++ " " ++ show end

export
Pretty Void StopReason where
  pretty EndInput = pretty "EndInput"
  pretty NoRuleApply = pretty "NoRuleApply"
  pretty (ComposeNotClosing start end) = "ComposeNotClosing" <++> pretty (show start) <++> pretty (show end)

tokenise : Lexer ->
           Tokenizer a ->
           (line, col : Int) -> SnocList (WithBounds a) ->
           List Char ->
           (SnocList (WithBounds a), (StopReason, Int, Int, List Char))
tokenise reject tokenizer line col acc [] = (acc, EndInput, (line, col, []))
tokenise reject tokenizer line col acc str
    = case scan reject [<] str of
           Just _ => (acc, (EndInput, line, col, str))
           Nothing => case getFirstMatch tokenizer acc str of
                           Right (acc', line', col', rest) =>
                               -- assert total because getFirstMatch must consume something
                               assert_total (tokenise reject tokenizer line' col' acc' rest)
                           Left reason => (acc, reason, (line, col, str))
  where

    -- get the next lexeme using the `Lexer` in argument, its position and the input
    -- Returns the new position, the lexeme parsed and the rest of the input
    -- If parsing the lexer fails, this returns `Nothing`
    getNext : (lexer : Lexer) -> (line, col : Int) ->
              (input : List Char) -> Maybe (String, Int, Int, List Char)
    getNext lexer line col str =
      let Just (token, rest) = scan lexer [<] str
            | _ => Nothing
          (line', col') = advance token line col
          tokenStr = fastPack $ token <>> []
       in pure (tokenStr, line', col', rest)

    getFirstMatch : Tokenizer a -> SnocList (WithBounds a) -> List Char ->
                    Either StopReason (SnocList (WithBounds a), Int, Int, List Char)
    getFirstMatch (Match lex fn) acc str
        = let Just (tok, line', col', rest) = getNext lex line col str
                | _ => Left NoRuleApply
              tok' = MkBounded (fn tok) False (MkBounds line col line' col')
           in Right (acc :< tok', line', col', rest)
    getFirstMatch (Compose begin mapBegin tagger middleFn endFn mapEnd) acc str
        = let Just (beginTok', line', col' , rest) = getNext begin line col str
                | Nothing => Left NoRuleApply
              tag = tagger beginTok'
              middle = middleFn tag
              end = endFn tag
              beginTok'' = MkBounded (mapBegin beginTok') False (MkBounds line col line' col')
              (acc', (reason, line'', col'', rest'')) =
                    assert_total $ tokenise end middle line' col' (acc :< beginTok'') rest
           in case reason of
                   ComposeNotClosing {} => Left reason
                   _ => let Just (endTok', lineEnd, colEnd, restEnd) =
                                getNext end line'' col'' rest''
                              | _ => Left $ ComposeNotClosing (line, col) (line', col')
                            endTok'' = MkBounded (mapEnd endTok') False (MkBounds line'' col'' lineEnd colEnd)
                         in Right (acc' :< endTok'', lineEnd, colEnd, restEnd)
    getFirstMatch (Alt t1 t2) acc str
        = case getFirstMatch t1 acc str of
               Right result => Right result
               Left reason@(ComposeNotClosing {}) => Left reason
               Left _ => getFirstMatch t2 acc str
    -- as the `Alt` of the alternatives that can start with the next
    -- character (the others would fail with `NoRuleApply`)
    getFirstMatch (Dispatch table alts) acc str
        = firstOf (case str of
                     (c :: _) => let code = ord c in
                                     if code < 128 then lookupTable code table else alts
                     [] => alts) acc str
      where
        firstOf : List (Tokenizer a) -> SnocList (WithBounds a) -> List Char ->
                  Either StopReason (SnocList (WithBounds a), Int, Int, List Char)
        firstOf [] acc str = Left NoRuleApply
        firstOf [t] acc str = getFirstMatch (assert_smaller table t) acc str
        firstOf (t :: ts) acc str
            = case getFirstMatch (assert_smaller table t) acc str of
                   Right result => Right result
                   Left reason@(ComposeNotClosing {}) => Left reason
                   Left _ => firstOf ts acc str

||| As `lexTo`, with the rest of the input as a list of characters, which
||| is only put back together into a string if it is needed: when the input
||| is lexed up to some point (the header of a module), the rest is most of
||| it.
export
lexToChars : Lexer ->
             Tokenizer a ->
             String ->
             (List (WithBounds a), (StopReason, Int, Int, List Char))
lexToChars reject tokenizer str
    = let (ts, reason, (l, c, str')) =
              tokenise reject tokenizer 0 0 [<] (fastUnpack str) in
          (ts <>> [], reason, (l, c, str'))

export
lexTo : Lexer ->
        Tokenizer a ->
        String ->
        (List (WithBounds a), (StopReason, Int, Int, String))
lexTo reject tokenizer str
    = let (ts, reason, (l, c, str')) = lexToChars reject tokenizer str in
          (ts, reason, (l, c, fastPack str'))

||| Given a tokenizer and an input string, return a list of recognised tokens,
||| and the line, column, and remainder of the input at the first point in the string
||| where there are no recognised tokens.
export
lex : Tokenizer a -> String -> (List (WithBounds a), (StopReason, Int, Int, String))
lex tokenizer str = lexTo (pred $ const False) tokenizer str
