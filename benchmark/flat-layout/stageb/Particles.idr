module Main

import FlatArr

record Particle where
  constructor MkParticle
  px : Double
  py : Double

%hint
layoutParticle : Layout Particle
layoutParticle = recordLayout "Main.MkParticle"

move : Particle -> Particle -> Particle
move p q = MkParticle (p.px + q.px) p.py

sweep : Int -> Int -> (1 _ : LinA Particle) -> LinA Particle
sweep n i a =
  if i >= n then a else
    let (mp # a) = mread a i
        (mq # a) = mread a (i + 1)
    in case mp of
         Nothing => sweep n (i + 1) a
         Just p => case mq of
           Nothing => sweep n (i + 1) a
           Just q => let (_ # a) = write a i (move p q) in sweep n (i + 1) a

main : IO ()
main = newA 10 (\a => done (sweep 10 0 a))
