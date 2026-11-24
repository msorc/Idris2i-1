import Data.Fin

-- literals whose conversion reduces to a constructor form still match
data Tag = MkTag String

FromString Tag where
  fromString s = MkTag s

f : Tag -> String
f "a" = "is a"
f _ = "other"

record Mod7 where
  constructor MkMod7
  val : Integer

Num Mod7 where
  fromInteger x = MkMod7 (x `mod` 7)
  MkMod7 a + MkMod7 b = MkMod7 ((a + b) `mod` 7)
  MkMod7 a * MkMod7 b = MkMod7 ((a * b) `mod` 7)

g : Mod7 -> String
g 3 = "three"
g _ = "other"

h : Fin 5 -> String
h 3 = "three"
h _ = "other"

main : IO ()
main = do putStrLn (f "a" ++ " " ++ f "b")
          putStrLn (g 10 ++ " " ++ g 4)
          putStrLn (h 3 ++ " " ++ h 4)
