||| A small line editor for the interactive REPL: Emacs-style key bindings
||| (as in readline), history, and syntax highlighting of the input as it is
||| typed.
|||
||| The terminal is only put into raw mode while a line is being read, so
||| anything that runs between two prompts (e.g. `:exec`) sees an ordinary
||| terminal.
module Idris.REPL.LineEditor

import Data.List
import Data.Maybe
import Data.String

import Libraries.Text.DisplayWidth
import Libraries.Text.Lexer.Tokenizer
import Parser.Lexer.Source

import System
import System.File
import System.Term

%default total

--------------------------------------------------------------------------------
-- Terminal access (support/c/idris_term.c)
--------------------------------------------------------------------------------

%foreign "C:idris2_termRawOn, libidris2_support, idris_term.h"
prim__termRawOn : PrimIO Int

%foreign "C:idris2_termRawOff, libidris2_support, idris_term.h"
prim__termRawOff : PrimIO ()

%foreign "C:idris2_readKey, libidris2_support, idris_term.h"
prim__readKey : PrimIO Int

%foreign "C:idris2_keyPending, libidris2_support, idris_term.h"
prim__keyPending : PrimIO Int

--------------------------------------------------------------------------------
-- Keys
--------------------------------------------------------------------------------

public export
data Key
  = KChar Char
  | KEnter
  | KBackspace
  | KDelete
  | KLeft
  | KRight
  | KUp
  | KDown
  | KHome
  | KEnd
  | KWordLeft
  | KWordRight
  | KKillToEnd
  | KKillToStart
  | KKillWordBack
  | KKillWordForward
  | KYank
  | KTranspose
  | KClearScreen
  | KInterrupt
  | KTab
  | KCtrlD -- deletes the next character, or ends the input on an empty line
  | KEof
  | KIgnore

-- The key codes of idris2_readKey
keySpecial, keyAlt : Int
keySpecial = 0x200000
keyAlt = 0x300000

decodeSpecial : Int -> Key
decodeSpecial 1 = KUp
decodeSpecial 2 = KDown
decodeSpecial 3 = KRight
decodeSpecial 4 = KLeft
decodeSpecial 5 = KHome
decodeSpecial 6 = KEnd
decodeSpecial 7 = KDelete
decodeSpecial 8 = KWordRight
decodeSpecial 9 = KWordLeft
decodeSpecial _ = KIgnore

decodeAlt : Int -> Key
decodeAlt 98 = KWordLeft        -- b
decodeAlt 102 = KWordRight      -- f
decodeAlt 100 = KKillWordForward -- d
decodeAlt 127 = KKillWordBack   -- backspace
decodeAlt _ = KIgnore

decodeControl : Int -> Key
decodeControl 1 = KHome
decodeControl 2 = KLeft
decodeControl 3 = KInterrupt
decodeControl 4 = KCtrlD
decodeControl 5 = KEnd
decodeControl 6 = KRight
decodeControl 8 = KBackspace
decodeControl 9 = KTab
decodeControl 10 = KEnter
decodeControl 11 = KKillToEnd
decodeControl 12 = KClearScreen
decodeControl 13 = KEnter
decodeControl 14 = KDown
decodeControl 16 = KUp
decodeControl 20 = KTranspose
decodeControl 21 = KKillToStart
decodeControl 23 = KKillWordBack
decodeControl 25 = KYank
decodeControl 127 = KBackspace
decodeControl _ = KIgnore

export
decodeKey : Int -> Key
decodeKey k =
  if k < 0 then KEof
  else if k >= keyAlt then decodeAlt (k - keyAlt)
  else if k >= keySpecial then decodeSpecial (k - keySpecial)
  else if k < 32 || k == 127 then decodeControl k
  else KChar (chr k)

--------------------------------------------------------------------------------
-- Editing
--------------------------------------------------------------------------------

public export
record Editor where
  constructor MkEditor
  ||| The text before the cursor, nearest character first
  before : List Char
  ||| The text after the cursor
  after : List Char
  ||| What the last kill command removed, in text order
  killed : List Char
  ||| The history, most recent entry first
  entries : List String
  ||| 0 is the line being typed, `n` is the `n`th history entry (from 1)
  position : Nat
  ||| The line being typed, while a history entry is shown
  draft : List Char

export
newEditor : (history : List String) -> Editor
newEditor history = MkEditor [] [] [] history 0 []

export
contents : Editor -> List Char
contents e = reverse e.before ++ e.after

-- (with the combining marks, so that the word-wise commands don't stop
-- between a letter and its accent)
isWordChar : Char -> Bool
isWordChar c = isAlphaNum c || c == '_' || c == '\'' || isZeroWidth c

||| What the word-wise commands skip over: separators, then a word
wordSpan : List Char -> (List Char, List Char)
wordSpan cs =
  let (sep, rest) = span (not . isWordChar) cs
      (word, rest') = span isWordChar rest
  in (sep ++ word, rest')

insertChar : Char -> Editor -> Editor
insertChar c = { before $= (c ::) }

-- The cursor moves, and Backspace and Delete delete, by what takes up a place
-- on the screen: a character with the zero width ones after it (combining
-- marks, variation selectors, joiners), so that the cursor is never between
-- a letter and its accent, where it would be shown in the wrong place.
-- (These are not the grapheme clusters of Unicode: emoji joined by U+200D,
-- for instance, are still several places.)  Transposing and the word-wise
-- commands work on code points.

||| The place before the cursor, nearest character first, and what is before
||| it (`before` is nearest first)
placeBefore : List Char -> (List Char, List Char)
placeBefore cs =
  let (marks, rest) = span isZeroWidth cs
  in case rest of
       (base :: rest') => (marks ++ [base], rest')
       [] => (marks, [])

||| The place after the cursor, and what is after it
placeAfter : List Char -> (List Char, List Char)
placeAfter [] = ([], [])
placeAfter (c :: cs) = let (marks, rest) = span isZeroWidth cs in (c :: marks, rest)

backspace : Editor -> Editor
backspace e = { before := snd (placeBefore e.before) } e

deleteChar : Editor -> Editor
deleteChar e = { after := snd (placeAfter e.after) } e

moveLeft : Editor -> Editor
moveLeft e =
  let (place, rest) = placeBefore e.before
  in { before := rest, after := reverse place ++ e.after } e

moveRight : Editor -> Editor
moveRight e =
  let (place, rest) = placeAfter e.after
  in { before := reverse place ++ e.before, after := rest } e

wordLeft : Editor -> Editor
wordLeft e =
  let (moved, rest) = wordSpan e.before
  in { before := rest, after := reverse moved ++ e.after } e

wordRight : Editor -> Editor
wordRight e =
  let (moved, rest) = wordSpan e.after
  in { before := reverse moved ++ e.before, after := rest } e

killToEnd : Editor -> Editor
killToEnd e = { after := [], killed := e.after } e

killToStart : Editor -> Editor
killToStart e = { before := [], killed := reverse e.before } e

killWordBack : Editor -> Editor
killWordBack e =
  let (moved, rest) = wordSpan e.before
  in { before := rest, killed := reverse moved } e

killWordForward : Editor -> Editor
killWordForward e =
  let (moved, rest) = wordSpan e.after
  in { after := rest, killed := moved } e

yank : Editor -> Editor
yank e = { before := reverse e.killed ++ e.before } e

transposeChars : Editor -> Editor
transposeChars e = case (e.before, e.after) of
  (b :: bs, a :: as) => { before := b :: a :: bs, after := as } e -- ..b|a.. => ..ab|..
  (b :: a :: bs, []) => { before := a :: b :: bs } e              -- ..ab| => ..ba|
  _ => e

||| What is shown at a history position
shown : Editor -> Nat -> List Char
shown e Z = e.draft
shown e (S n) = case drop n e.entries of
  [] => e.draft
  (h :: _) => unpack h

goto : Nat -> Editor -> Editor
goto n e =
  -- remember the line being typed when first leaving it
  let draft = if e.position == 0 then contents e else e.draft
      e' = { draft := draft } e
  in { position := n, before := reverse (shown e' n), after := [] } e'

historyUp : Editor -> Editor
historyUp e = if e.position < length e.entries then goto (S e.position) e else e

historyDown : Editor -> Editor
historyDown e = case e.position of
  Z => e
  S n => goto n e

||| What to do after a key
public export
data Step
  = Edited Editor
  | Cleared Editor   -- redraw on a cleared screen
  | Completion       -- complete the word before the cursor
  | Submit
  | Abort            -- the line was discarded (Ctrl-C)
  | EndOfInput

export
step : Key -> Editor -> Step
step (KChar c) e = Edited (insertChar c e)
step KEnter e = Submit
step KBackspace e = Edited (backspace e)
step KDelete e = Edited (deleteChar e)
step KLeft e = Edited (moveLeft e)
step KRight e = Edited (moveRight e)
step KUp e = Edited (historyUp e)
step KDown e = Edited (historyDown e)
step KHome e = Edited ({ before := [], after := contents e } e)
step KEnd e = Edited ({ before := reverse (contents e), after := [] } e)
step KWordLeft e = Edited (wordLeft e)
step KWordRight e = Edited (wordRight e)
step KKillToEnd e = Edited (killToEnd e)
step KKillToStart e = Edited (killToStart e)
step KKillWordBack e = Edited (killWordBack e)
step KKillWordForward e = Edited (killWordForward e)
step KYank e = Edited (yank e)
step KTranspose e = Edited (transposeChars e)
step KClearScreen e = Cleared e
step KTab e = Completion
step KInterrupt e = Abort
step KCtrlD e = case (e.before, e.after) of
  ([], []) => EndOfInput
  _ => Edited (deleteChar e)
step KEof e = EndOfInput
step KIgnore e = Edited e

--------------------------------------------------------------------------------
-- Syntax highlighting
--------------------------------------------------------------------------------

-- SGR parameters
keywordStyle, literalStyle, commentStyle, holeStyle, nameStyle, commandStyle : String
keywordStyle = "1;35"
literalStyle = "32"
commentStyle = "90"
holeStyle = "33"
nameStyle = "94"
commandStyle = "95"

isCapitalised : String -> Bool
isCapitalised s = case strM s of
  StrCons c _ => isUpper c
  StrNil => False

tokenStyle : Token -> String
tokenStyle (Keyword _) = keywordStyle
tokenStyle (CharLit _) = literalStyle
tokenStyle (DoubleLit _) = literalStyle
tokenStyle (IntegerLit _) = literalStyle
tokenStyle (StringBegin _ _) = literalStyle
tokenStyle StringEnd = literalStyle
tokenStyle (StringLit _) = literalStyle
tokenStyle (HoleIdent _) = holeStyle
tokenStyle (Ident n) = if isCapitalised n then nameStyle else ""
tokenStyle (DotSepIdent _ n) = if isCapitalised n then nameStyle else ""
tokenStyle (DocComment _) = commentStyle
tokenStyle (Pragma _) = commandStyle
tokenStyle (CGDirective _) = commandStyle
tokenStyle _ = ""

||| Where a style applies: the first column and the one after the last
Span : Type
Span = (Int, Int, String)

tokenSpan : WithBounds Token -> Maybe Span
tokenSpan t =
  let style = tokenStyle t.val
      b = t.bounds
  in if style == "" || b.startLine /= 0 || b.endLine /= 0
        then Nothing
        else Just (b.startCol, b.endCol, style)

commentSpan : WithBounds () -> Maybe Span
commentSpan c =
  let b = c.bounds
  in if b.startLine /= 0 || b.endLine /= 0
        then Nothing
        else Just (b.startCol, b.endCol, commentStyle)

||| The style of each of `n` characters (the spans don't overlap)
paint : Nat -> List Span -> List String
paint n spans = go 0 n (sortBy (\(s, _, _), (s', _, _) => compare s s') spans)
  where
    -- the spans that are not over yet, in order
    go : Int -> Nat -> List Span -> List String
    go i Z _ = []
    go i (S k) ss =
      case dropWhile (\(_, e, _) => e <= i) ss of
        [] => "" :: go (i + 1) k []
        ss'@((s, _, style) :: _) =>
          (if s <= i then style else "") :: go (i + 1) k ss'

||| The style of each character of some Idris code. If the end of the code
||| can't be lexed (yet), say in an unfinished string, only the part before
||| that is highlighted.
codeStyles : List Char -> List String
codeStyles cs =
  case lex (pack cs) of
    Right (comments, toks) => paint (length cs) (spans comments toks)
    Left (_, _, col, _) =>
      let ok = take (integerToNat (cast col)) cs
      in case lex (pack ok) of
           Right (comments, toks) => paint (length cs) (spans comments toks)
           Left _ => replicate (length cs) ""
  where
    spans : List (WithBounds ()) -> List (WithBounds Token) -> List Span
    spans comments toks = mapMaybe commentSpan comments ++ mapMaybe tokenSpan toks

-- The arguments of these REPL commands are not Idris code
fileCommands : List String
fileCommands = ["l", "load", "cd", "c", "compile", "e", "edit", "sh", "shell"]

||| The style of each character of a line typed at the prompt: `:command`s and
||| their arguments, or an expression
export
lineStyles : List Char -> List String
lineStyles cs =
  let (blanks, rest) = span isSpace cs
  in case rest of
       ':' :: more =>
         let (name, args) = span (\c => isAlpha c || c == '?') more
         in replicate (length blanks) ""
            ++ replicate (S (length name)) commandStyle
            ++ (if pack name `elem` fileCommands
                   then replicate (length args) ""
                   else codeStyles args)
       _ => codeStyles cs

||| The line with SGR escapes to show it in its styles
export
highlight : List Char -> String
highlight cs = fastConcat (go [] [] (zip cs (lineStyles cs)) "")
  where
    sgr : String -> String
    sgr "" = "\ESC[0m"
    sgr style = "\ESC[0;" ++ style ++ "m"

    -- the pieces of the output so far and the characters in the style that is
    -- on, both last first
    go : List String -> List Char -> List (Char, String) -> String -> List String
    go acc run [] current =
      let acc' = pack (reverse run) :: acc
      in reverse (if current == "" then acc' else sgr "" :: acc')
    go acc run ((c, style) :: rest) current =
      if style == current
         then go acc (c :: run) rest current
         else go (sgr style :: pack (reverse run) :: acc) [c] rest style

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

escUp : Nat -> String
escUp Z = ""
escUp n = "\ESC[" ++ show n ++ "A"

escRight : Nat -> String
escRight Z = ""
escRight n = "\ESC[" ++ show n ++ "C"

||| The characters of a text that are shown, without its escape sequences
||| (CSI sequences, such as colours, and two character ones)
export
shownChars : List Char -> List Char
shownChars ('\ESC' :: '[' :: cs) =
  shownChars (assert_smaller cs (drop 1 (dropWhile (\c => c < '@' || c > '~') cs)))
shownChars ('\ESC' :: _ :: cs) = shownChars cs
shownChars ['\ESC'] = []
shownChars (c :: cs) = c :: shownChars cs
shownChars [] = []

||| Where the terminal goes on after it has shown a character: the row, and
||| the column after the character, which is `cols` when it ends at the right
||| edge, as the terminal goes to the next row only when more is shown.  A
||| wide character that doesn't fit in the rest of a row is shown on the next
||| one.
advance : (cols : Int) -> (Int, Int) -> Char -> (Int, Int)
advance cols (row, col) c =
  let w = cast (charWidth c)
  in if w > 0 && col + w > cols then (row + 1, w) else (row, col + w)

||| The escapes that redraw the prompt and the line, which may be longer than
||| the terminal is wide, and put the cursor in its place.  The positions are
||| in columns of the terminal (see `Libraries.Text.DisplayWidth`), so wide
||| characters take up two and combining marks none.
|||
||| @ prompt   the prompt (it may have escapes, such as colours)
||| @ text     the line, as it is shown (with escapes)
||| @ line     the characters of the line
||| @ cursor   how many characters of the line are before the cursor
||| @ termCols the width of the terminal (0 if unknown)
||| @ oldRow   the row of the cursor now, counted from the prompt
||| Returns the escapes and the new row of the cursor.
export
frame : (prompt : String) -> (text : String) -> (line : List Char) ->
        (cursor, termCols, oldRow : Nat) -> (String, Nat)
frame prompt text line cursor termCols oldRow =
  let cols : Int = if termCols < 2 then 80 else cast termCols
      (left, right) = splitAt cursor line
      start = foldl (advance cols) (0, 0) (shownChars (unpack prompt))
      here = foldl (advance cols) start left
      (endRow, endCol) = foldl (advance cols) here right
      -- the cursor is at the end of the output, which is on this row; text that
      -- ends at the right edge needs a line break to get the cursor off it
      wrap = endCol >= cols
      shownEnd = if wrap then endRow + 1 else endRow
      -- the cursor is on the character after it (a wide one may not fit in
      -- this row), or after the end of the line
      next : Int = case right of
                     (c :: _) => max 1 (cast (charWidth c))
                     [] => 1
      (row, col) = if snd here + next > cols then (fst here + 1, 0) else here
      toNat : Int -> Nat
      toNat = integerToNat . cast
  in ( escUp oldRow ++ "\r\ESC[J" ++ prompt ++ text
       ++ (if wrap then "\r\n" else "")
       ++ escUp (toNat (shownEnd - row)) ++ "\r" ++ escRight (toNat col)
     , toNat row)

--------------------------------------------------------------------------------
-- Completion
--------------------------------------------------------------------------------

public export
data Completed
  = NoMatch
  | Replace Editor              -- the line, completed as far as it is certain
  | ShowList Editor (List String) -- the line as it is, and what it could be

commonPrefix : List Char -> List Char -> List Char
commonPrefix (x :: xs) (y :: ys) = if x == y then x :: commonPrefix xs ys else []
commonPrefix _ _ = []

||| Apply the candidates for the word before the cursor.
|||
||| @ completion the part of the line before the word, and the words that it
|||              could be completed to (as the compiler's `completion`)
export
applyCompletion : Editor -> (completion : Maybe (String, List String)) -> Completed
applyCompletion e Nothing = NoMatch
applyCompletion e (Just (skipped, candidates)) =
  let line = reverse e.before
      skip = unpack skipped
      word = drop (length skip) line
      options = nub (sort (filter (isPrefixOf word . unpack) candidates))
      replaceWord : List Char -> Editor
      replaceWord new = { before := reverse (skip ++ new) } e
  in if not (skip `isPrefixOf` line)
        then NoMatch
        else case options of
          [] => NoMatch
          [only] =>
            -- the word is finished
            let space = case e.after of
                          (' ' :: _) => []
                          _ => [' ']
            in Replace (replaceWord (unpack only ++ space))
          (first :: others) =>
            let common = foldl commonPrefix (unpack first) (map unpack others)
            in if length common > length word
                  then Replace (replaceWord common)
                  else ShowList e options

||| What is in front of the cursor, to complete
export
beforeCursor : Editor -> String
beforeCursor e = pack (reverse e.before)

maxListed : Nat
maxListed = 100

chunks : Nat -> List a -> List (List a)
chunks _ [] = []
chunks Z xs = [xs]
chunks n xs = let (row, rest) = splitAt n xs in row :: assert_total (chunks n rest)

||| The candidates, in columns that fit the width of the terminal, one line
||| of the table per line of text (each ending in a line break)
export
columns : (width : Nat) -> List String -> String
columns width candidates =
  let shown = take maxListed candidates
      cell = foldl (\m, c => max m (stringWidth c)) 0 shown + 2
      -- cell is at least 2, so the divisor is not zero
      perRow = max 1 (integerToNat (cast (assert_total $
                                            cast {to = Int} (if width < 2 then 80 else width)
                                              `div` cast {to = Int} cell)))
      pad : String -> String
      pad c = c ++ pack (replicate (cell `minus` stringWidth c) ' ')
      row : List String -> String
      row cs = case reverse cs of
                 [] => ""
                 (lst :: before) => fastConcat (map pad (reverse before)) ++ lst
      more = length candidates `minus` maxListed
  in fastConcat (map (\line => row line ++ "\r\n") (chunks perRow shown))
     ++ (if more > 0 then "(" ++ show more ++ " more)\r\n" else "")

--------------------------------------------------------------------------------
-- Reading a line
--------------------------------------------------------------------------------

||| A line that is being edited, while something else (completion) is done
public export
record Session where
  constructor MkSession
  prompt : String
  colour : Bool
  editor : Editor
  row : Nat

public export
data LineResult
  = Line String
  | EndOfFile
  | ||| Line editing isn't possible, nothing has been done
    Unavailable
  | ||| The editor waits for the candidates to complete the part of the line
    ||| before the cursor (see `beforeCursor`): continue with `resumeEdit`
    Complete Session

export
lineEditingEnabled : IO Bool
lineEditingEnabled = do
  disabled <- getEnv "IDRIS2_LINE_EDITING"
  term <- getEnv "TERM"
  inputTTY <- isTTY stdin
  outputTTY <- isTTY stdout
  pure $ inputTTY && outputTTY
      && disabled /= Just "0"
      && maybe False (/= "dumb") term

||| Draw the line, and return the row that the cursor is on
draw : (prompt : String) -> (colour : Bool) -> Editor -> (row : Nat) -> IO Nat
draw prompt colour e row = do
  cols <- getTermCols
  let line = contents e
      text = if colour then highlight line else pack line
      (out, row') = frame prompt text line (length e.before)
                          (integerToNat (cast cols)) row
  putStr out
  fflush stdout
  pure row'

||| Draw the line with the cursor at the end, to continue below it
finish : (prompt : String) -> (colour : Bool) -> Editor -> (row : Nat) -> IO ()
finish prompt colour e row = do
  _ <- draw prompt colour ({ before := reverse (contents e), after := [] } e) row
  pure ()

covering
loop : Session -> IO LineResult
loop s@(MkSession prompt colour e row) = do
  key <- primIO prim__readKey
  case step (decodeKey key) e of
    Edited e' => do
      -- while more keys are waiting (e.g. pasted text), draw only at the end
      pending <- primIO prim__keyPending
      row' <- if pending /= 0 then pure row else draw prompt colour e' row
      loop ({ editor := e', row := row' } s)
    Cleared e' => do
      putStr "\ESC[H\ESC[2J"
      row' <- draw prompt colour e' 0
      loop ({ editor := e', row := row' } s)
    Completion => do
      -- the line may not have been drawn yet (see `Edited`)
      row' <- draw prompt colour e row
      pure (Complete ({ row := row' } s))
    Submit => do
      finish prompt colour e row
      putStr "\r\n"
      fflush stdout
      primIO prim__termRawOff
      pure (Line (pack (contents e)))
    Abort => do
      finish prompt colour e row
      putStr "^C\r\n"
      fflush stdout
      primIO prim__termRawOff
      pure (Line "")
    EndOfInput => do
      primIO prim__termRawOff
      pure EndOfFile

||| Read a line at the prompt, with the user editing it, until they submit it
||| (or ask for a completion).
|||
||| @ prompt  the prompt (it may have escapes, such as colours)
||| @ colour  whether to highlight the line as it is typed
||| @ history the previous lines, the most recent one first
export covering
editLine : (prompt : String) -> (colour : Bool) -> (history : List String) ->
           IO LineResult
editLine prompt colour history = do
  ok <- primIO prim__termRawOn
  if ok == 0
     then pure Unavailable
     else do
       putStr ("\r\ESC[J" ++ prompt)
       fflush stdout
       loop (MkSession prompt colour (newEditor history) 0)

||| Go on editing after a `Complete`, with the candidates for the word before
||| the cursor (as the compiler's `completion` gives them).
export covering
resumeEdit : Session -> Maybe (String, List String) -> IO LineResult
resumeEdit s candidates =
  case applyCompletion s.editor candidates of
    NoMatch => do
      putStr "\a"
      fflush stdout
      loop s
    Replace e => do
      row <- draw s.prompt s.colour e s.row
      loop ({ editor := e, row := row } s)
    ShowList e options => do
      -- list them below the line, which stays as it is
      finish s.prompt s.colour e s.row
      putStr "\r\n"
      cols <- getTermCols
      putStr (columns (integerToNat (cast cols)) options)
      row <- draw s.prompt s.colour e 0
      loop ({ editor := e, row := row } s)

--------------------------------------------------------------------------------
-- History file
--------------------------------------------------------------------------------

maxHistory : Nat
maxHistory = 1000

||| The history file: $IDRIS2_HISTORY_FILE (empty for no file), or
||| ~/.idris2_history.
historyFile : IO (Maybe String)
historyFile = do
  explicit <- getEnv "IDRIS2_HISTORY_FILE"
  case explicit of
    Just "" => pure Nothing
    Just file => pure (Just file)
    Nothing => map (++ "/.idris2_history") <$> getEnv "HOME"

||| The lines saved from earlier sessions, the most recent first
export covering
loadHistory : IO (List String)
loadHistory = do
  Just file <- historyFile
    | Nothing => pure []
  Right content <- readFile file
    | Left _ => pure []
  let saved = filter (/= "") (lines content)
      recent = drop (length saved `minus` maxHistory) saved
  -- don't let the file grow for ever
  when (length saved > 2 * maxHistory) $
    ignore $ writeFile file (unlines recent)
  pure (reverse recent)

||| Add a line to the history file
export
saveHistoryLine : String -> IO ()
saveHistoryLine line = do
  Just file <- historyFile
    | Nothing => pure ()
  existed <- exists file
  Right () <- appendFile file (line ++ "\n")
    | Left _ => pure ()
  -- the history may contain things not meant for others
  unless existed $ ignore $ chmodRaw file 0o600
