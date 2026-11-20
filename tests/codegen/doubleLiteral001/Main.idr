module Main

record P where
  constructor MkP
  px : Double
  hits : Int

-- The integer literals at the type Double, in a `let` without a type, are
-- elaborated as `fromInteger 0`, and not reduced: the cast of the Integer to
-- a Double is folded when the Double is exact (see Compiler.Opts.ConstantFold).
-- Those of the Integers that are not exact Doubles are not folded.
bounce : P -> P
bounce p =
  let q = if p.px < 0 then { px := - p.px, hits $= (+1) } p
          else if p.px > 1000 then { px := 2000 - p.px, hits $= (+1) } p
          else p
  in q

far : P -> Double
far p = let x = 9007199254740993 + p.px in x

main : IO ()
main = do
  printLn (map (px . bounce) [MkP (-1.5) 0, MkP 1500 0, MkP 3 0])
  printLn (far (MkP 0 0))
