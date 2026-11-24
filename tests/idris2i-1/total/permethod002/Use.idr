-- What a function in another module uses of a dictionary, and whether it is
-- covering once the methods are counted, is seen through the TTC of its
-- module, which was checked without --method-totality
module Use

import Lib

%default total

viaKeepTwice : T -> T
viaKeepTwice = keepTwice

viaPickOnce : T -> T
viaPickOnce = pickOnce

viaUseKeep : T -> T
viaUseKeep = useKeep

viaUsePick : T -> T
viaUsePick = usePick

viaInts : List Int
viaInts = ints 10

direct : T -> T
direct = keep
