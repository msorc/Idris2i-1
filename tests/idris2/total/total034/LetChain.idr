module LetChain

%default total

step : Nat -> Nat -> Nat
step a b = a

-- Each let uses the previous variable twice, so substituting the values of
-- the lets for their variables makes the right hand sides exponentially big
chain : Nat -> Nat
chain Z = Z
chain (S k)
  = let k' = k in
    let x0 = k' in
    let x1 = step x0 x0 in
    let x2 = step x1 x1 in
    let x3 = step x2 x2 in
    let x4 = step x3 x3 in
    let x5 = step x4 x4 in
    let x6 = step x5 x5 in
    let x7 = step x6 x6 in
    let x8 = step x7 x7 in
    let x9 = step x8 x8 in
    let x10 = step x9 x9 in
    let x11 = step x10 x10 in
    let x12 = step x11 x11 in
    let x13 = step x12 x12 in
    let x14 = step x13 x13 in
    let x15 = step x14 x14 in
    let x16 = step x15 x15 in
    let x17 = step x16 x16 in
    let x18 = step x17 x17 in
    let x19 = step x18 x18 in
    let x20 = step x19 x19 in
    let x21 = step x20 x20 in
    let x22 = step x21 x21 in
    let x23 = step x22 x22 in
    let x24 = step x23 x23 in
    let x25 = step x24 x24 in
    let x26 = step x25 x25 in
    let x27 = step x26 x26 in
    let x28 = step x27 x27 in
    let x29 = step x28 x28 in
    let x30 = step x29 x29 in
    plus (chain k') x30

covering
loop : Nat -> Nat
loop Z = Z
loop (S k)
  = let n = S k in
    let x0 = n in
    let x1 = step x0 x0 in
    let x2 = step x1 x1 in
    let x3 = step x2 x2 in
    let x4 = step x3 x3 in
    let x5 = step x4 x4 in
    let x6 = step x5 x5 in
    let x7 = step x6 x6 in
    let x8 = step x7 x7 in
    let x9 = step x8 x8 in
    let x10 = step x9 x9 in
    let x11 = step x10 x10 in
    let x12 = step x11 x11 in
    let x13 = step x12 x12 in
    let x14 = step x13 x13 in
    let x15 = step x14 x14 in
    let x16 = step x15 x15 in
    let x17 = step x16 x16 in
    let x18 = step x17 x17 in
    let x19 = step x18 x18 in
    let x20 = step x19 x19 in
    let x21 = step x20 x20 in
    let x22 = step x21 x21 in
    let x23 = step x22 x22 in
    let x24 = step x23 x23 in
    let x25 = step x24 x24 in
    let x26 = step x25 x25 in
    let x27 = step x26 x26 in
    let x28 = step x27 x27 in
    let x29 = step x28 x28 in
    let x30 = step x29 x29 in
    plus (loop n) x30

inCase : Nat -> Nat
inCase n
  = case n of
      Z => Z
      S k =>
        let x0 = k in
        let x1 = step x0 x0 in
        let x2 = step x1 x1 in
        let x3 = step x2 x2 in
        let x4 = step x3 x3 in
        let x5 = step x4 x4 in
        let x6 = step x5 x5 in
        let x7 = step x6 x6 in
        let x8 = step x7 x7 in
        let x9 = step x8 x8 in
        let x10 = step x9 x9 in
        let x11 = step x10 x10 in
        let x12 = step x11 x11 in
        let x13 = step x12 x12 in
        let x14 = step x13 x13 in
        let x15 = step x14 x14 in
        let x16 = step x15 x15 in
        let x17 = step x16 x16 in
        let x18 = step x17 x17 in
        let x19 = step x18 x18 in
        let x20 = step x19 x19 in
        let x21 = step x20 x20 in
        let x22 = step x21 x21 in
        let x23 = step x22 x22 in
        let x24 = step x23 x23 in
        let x25 = step x24 x24 in
        let x26 = step x25 x25 in
        let x27 = step x26 x26 in
        let x28 = step x27 x27 in
        let x29 = step x28 x28 in
        let x30 = step x29 x29 in
        plus (inCase k) x30

prims : Int -> Int
prims x0
  = let x1 = prim__add_Int x0 x0 in
    let x2 = prim__add_Int x1 x1 in
    let x3 = prim__add_Int x2 x2 in
    let x4 = prim__add_Int x3 x3 in
    let x5 = prim__add_Int x4 x4 in
    let x6 = prim__add_Int x5 x5 in
    let x7 = prim__add_Int x6 x6 in
    let x8 = prim__add_Int x7 x7 in
    let x9 = prim__add_Int x8 x8 in
    let x10 = prim__add_Int x9 x9 in
    let x11 = prim__add_Int x10 x10 in
    let x12 = prim__add_Int x11 x11 in
    let x13 = prim__add_Int x12 x12 in
    let x14 = prim__add_Int x13 x13 in
    let x15 = prim__add_Int x14 x14 in
    let x16 = prim__add_Int x15 x15 in
    let x17 = prim__add_Int x16 x16 in
    let x18 = prim__add_Int x17 x17 in
    let x19 = prim__add_Int x18 x18 in
    let x20 = prim__add_Int x19 x19 in
    let x21 = prim__add_Int x20 x20 in
    let x22 = prim__add_Int x21 x21 in
    let x23 = prim__add_Int x22 x22 in
    let x24 = prim__add_Int x23 x23 in
    let x25 = prim__add_Int x24 x24 in
    let x26 = prim__add_Int x25 x25 in
    let x27 = prim__add_Int x26 x26 in
    let x28 = prim__add_Int x27 x27 in
    let x29 = prim__add_Int x28 x28 in
    let x30 = prim__add_Int x29 x29 in
    x30
