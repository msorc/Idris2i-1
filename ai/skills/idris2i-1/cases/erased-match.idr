-- expect: E0606
data Flag = On | Off

f : (0 flag : Flag) -> Nat
f On = 1
f Off = 0
