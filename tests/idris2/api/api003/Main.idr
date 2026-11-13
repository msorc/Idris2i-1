module Main

-- The pure parts of the REPL's line editor: key bindings, highlighting and
-- drawing. Reading keys from the terminal is not tested.

import Data.List
import Data.String

import Idris.REPL.LineEditor

keys : String -> List Key
keys = map KChar . unpack

||| Show the text with the cursor as `|`
render : Editor -> String
render e = pack (reverse e.before) ++ "|" ++ pack e.after

play : List Key -> Editor -> String
play [] e = render e
play (k :: ks) e = case step k e of
  Edited e' => play ks e'
  Cleared e' => play ks e'
  Completion => "completion"
  Submit => "submitted " ++ pack (contents e)
  Abort => "aborted"
  EndOfInput => "end of input"

test : String -> Editor -> List Key -> IO ()
test name e ks = putStrLn (name ++ ": " ++ play ks e)

typing : String -> Editor
typing = foldl (\e, c => case step (KChar c) e of
                            Edited e' => e'
                            _ => e) (newEditor []) . unpack

complete : String -> Maybe (String, List String) -> IO ()
complete typed candidates = putStrLn $ typed ++ " => " ++
  case applyCompletion (typing typed) candidates of
    NoMatch => "no match"
    Replace e => "replace " ++ render e
    ShowList e options => "list " ++ show options ++ " " ++ render e

-- escapes visible, and nothing else on the line
visible : String -> String
visible = fastConcat . map (\c => if c == '\ESC' then "<E>" else singleton c) . unpack

hl : String -> IO ()
hl s = putStrLn (visible (highlight (unpack s)))

-- prompt, text, cursor, width of the terminal, cursor row now
draw : String -> Nat -> Nat -> Nat -> IO ()
draw text cursor cols row = do
  let (out, row') = frame "Main> " text (length text) cursor cols row
  putStrLn (show (visible out) ++ " row " ++ show row')

main : IO ()
main = do
  let new = newEditor ["second", "first"]
  test "type" new (keys "abc")
  test "left, insert" new (keys "abc" ++ [KLeft, KChar 'X'])
  test "backspace" new (keys "abc" ++ [KLeft, KBackspace])
  test "delete" new (keys "abc" ++ [KHome, KDelete])
  test "end" new (keys "abc" ++ [KHome, KEnd])
  test "word left" new (keys "foo bar_baz  qux" ++ [KWordLeft, KWordLeft])
  test "word right" new (keys "foo bar_baz  qux" ++ [KHome, KWordRight, KWordRight])
  test "kill to end" new (keys "foo bar" ++ [KHome, KRight, KKillToEnd])
  test "kill to start, yank" new (keys "foo bar" ++ [KLeft, KKillToStart, KEnd, KYank])
  test "kill word back" new (keys "foo bar" ++ [KKillWordBack])
  test "kill word back, yank" new (keys "foo bar" ++ [KKillWordBack, KHome, KYank])
  test "kill word forward" new (keys "foo bar" ++ [KHome, KKillWordForward])
  test "transpose in the middle" new (keys "abcd" ++ [KLeft, KLeft, KTranspose])
  test "transpose at the end" new (keys "abcd" ++ [KTranspose])
  test "ctrl-d in text" new (keys "ab" ++ [KHome, KCtrlD])
  test "ctrl-d on an empty line" new [KCtrlD]
  test "enter" new (keys "x" ++ [KEnter])
  test "ctrl-c" new (keys "x" ++ [KInterrupt])
  test "history up" new [KUp]
  test "history up twice" new [KUp, KUp]
  test "history up too far" new [KUp, KUp, KUp]
  test "history down" new [KUp, KUp, KDown]
  test "history keeps the draft" new (keys "draft" ++ [KUp, KDown])
  test "history, then edit" new [KUp, KChar '!']
  -- the keys the terminal sends
  test "decode" new (map decodeKey [97, 0x3b1, 1, 0x200001, 0x300062, 127] ++ [KChar 'z'])
  test "decode ctrl-c" new (map decodeKey [97, 3])
  test "decode end of input" new (map decodeKey [97, -1])
  test "decode ctrl-a" new (keys "ab" ++ map decodeKey [1])
  test "decode ctrl-d" new (map decodeKey [4])
  test "decode unknown" new (keys "ab" ++ map decodeKey [0x20000a, 9, 0x300099])
  test "decode non-ASCII" new (map decodeKey [0x3bb, 0x1f600])
  -- completion
  test "tab" new (keys "ab" ++ [KTab])
  complete "ma" (Just ("", ["map", "mapM", "maybe"]))
  complete "ma" (Just ("", ["maybe"]))
  complete "x + ma" (Just ("x + ", ["maybe"]))
  complete ":t ma" (Just (":t ", ["maybe", "map"]))
  complete "ma" (Just ("", ["map", "mapM", "map"]))
  complete "ma" (Just ("", ["mapM", "map"]))
  complete "m" (Just ("", ["map", "maybe", "max"]))
  complete "ma" (Just ("", ["map", "mat"]))
  complete "ma" Nothing
  complete "ma" (Just ("", []))
  complete "ma" (Just ("zz", ["map"]))
  complete "ma" (Just ("", ["xmap"]))
  complete "λma" (Just ("λ", ["map"]))
  putStr (columns 30 ["alpha", "beta", "gamma", "delta", "epsilon"])
  putStr (columns 0 ["a", "b"])
  putStr (columns 10 ["averylongcandidate", "b"])
  putStr (columns 80 (map show [1 .. the Nat 103]))
  -- highlighting
  hl "plus 1 2"
  hl "Just (x + 1)"
  hl "let x = \"hi\" in x"
  hl "\\x => ?hole x -- comment"
  hl "'a' + 0x10 + 1.5"
  hl "Data.List.length xs"
  hl "  :t Nat -> Type"
  hl ":doc Maybe"
  hl ":l My/File.idr"
  hl ":cd ../some where"
  hl "\"unfinished"
  hl "1 + \"unfinished"
  hl "λx => Ünï 1"
  hl ""
  -- drawing
  draw "abc" 3 80 0
  draw "abc" 1 80 0
  draw "abcdefghijklmnop" 16 10 0
  draw "abcdefghijklmnop" 4 10 2
  draw "abcd" 4 10 0
  draw "abcd" 2 10 1
  draw "" 0 6 0
  draw "abc" 3 0 0
