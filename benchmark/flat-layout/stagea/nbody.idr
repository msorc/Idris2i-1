-- N-body, in the style of the benchmarks game: five bodies of records of
-- Double fields, in a list, advanced in steps.  Input: the number of steps.
module Main

import Data.String

record Body where
  constructor MkBody
  x, y, z, vx, vy, vz, mass : Double

solarMass : Double
solarMass = 4.0 * pi * pi

daysPerYear : Double
daysPerYear = 365.24

bodies : List Body
bodies =
  [ MkBody 0 0 0 0 0 0 solarMass
  , MkBody 4.84143144246472090e+00 (-1.16032004402742839e+00) (-1.03622044471123109e-01)
           (1.66007664274403694e-03 * daysPerYear) (7.69901118419740425e-03 * daysPerYear)
           (-6.90460016972063023e-05 * daysPerYear) (9.54791938424326609e-04 * solarMass)
  , MkBody 8.34336671824457987e+00 4.12479856412430479e+00 (-4.03523417114321381e-01)
           (-2.76742510726862411e-03 * daysPerYear) (4.99852801234917238e-03 * daysPerYear)
           (2.30417297573763929e-05 * daysPerYear) (2.85885980666130812e-04 * solarMass)
  , MkBody 1.28943695621391310e+01 (-1.51111514016986312e+01) (-2.23307578892655734e-01)
           (2.96460137564761618e-03 * daysPerYear) (2.37847173959480950e-03 * daysPerYear)
           (-2.96589568540237556e-05 * daysPerYear) (4.36624404335156298e-05 * solarMass)
  , MkBody 1.53796971148509165e+01 (-2.59193146099879641e+01) 1.79258772950371181e-01
           (2.68067772490389322e-03 * daysPerYear) (1.62824170038242295e-03 * daysPerYear)
           (-9.51592254519715870e-05 * daysPerYear) (5.15138902046611451e-05 * solarMass)
  ]

-- The velocity of `b` after the pull of `o` during `dt`.
pull : Double -> Body -> Body -> Body
pull dt b o =
  let dx = b.x - o.x
      dy = b.y - o.y
      dz = b.z - o.z
      d2 = dx * dx + dy * dy + dz * dz
      mag = dt / (d2 * sqrt d2)
  in { vx := b.vx - dx * o.mass * mag
     , vy := b.vy - dy * o.mass * mag
     , vz := b.vz - dz * o.mass * mag } b

pullAll : Double -> Body -> List Body -> Body
pullAll dt b [] = b
pullAll dt b (o :: os) = pullAll dt (pull dt b o) os

-- Every body pulled by the others (the bodies before it already moved
-- their velocities, as the reference program does it pairwise).
velocities : Double -> List Body -> List Body -> List Body
velocities dt done [] = reverse done
velocities dt done (b :: rest) =
  velocities dt (pullAll dt b (done ++ rest) :: done) rest

move : Double -> Body -> Body
move dt b = { x := b.x + dt * b.vx, y := b.y + dt * b.vy, z := b.z + dt * b.vz } b

step : Double -> List Body -> List Body
step dt bs = map (move dt) (velocities dt [] bs)

steps : Int -> List Body -> List Body
steps 0 bs = bs
steps k bs = steps (k - 1) (step 0.01 bs)

energy : List Body -> Double
energy bs = go bs 0.0
  where
    pot : Body -> List Body -> Double -> Double
    pot b [] e = e
    pot b (o :: os) e =
      let dx = b.x - o.x
          dy = b.y - o.y
          dz = b.z - o.z
      in pot b os (e - b.mass * o.mass / sqrt (dx * dx + dy * dy + dz * dz))
    go : List Body -> Double -> Double
    go [] e = e
    go (b :: os) e =
      go os (pot b os (e + 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)))

main : IO ()
main = do
  line <- getLine
  let n = cast {to = Int} (trim line)
  let bs = steps n bodies
  printLn (cast {to = Int} (energy bs * 1.0e9))
