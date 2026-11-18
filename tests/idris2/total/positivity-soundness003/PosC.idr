module PosC

import PosB

%default total

-- A legitimate nested type through positive containers (Tree, Box) that this
-- module does not see.
data Rose : Type where
  MkRose : Int -> Wrap Rose -> Rose
  Tip : Rose

rose : Rose
rose = MkRose 1 (wrap (MkRose 2 (wrap Tip)))
