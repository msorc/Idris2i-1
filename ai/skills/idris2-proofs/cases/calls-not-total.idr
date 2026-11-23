-- expect: E0702 E0703
-- Both codes mean "calls a function that is not total". Which one is reported
-- depends on the order of checking: the first total caller of loop gets E0703,
-- a later one E0702, with the same message.

loop : Nat -> Nat
loop n = loop n

total
first : Nat -> Nat
first n = loop n

total
second : Nat -> Nat
second n = loop n
