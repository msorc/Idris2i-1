Port `Bank.hs` to Idris 2 as `Bank.idr`, so that
`idris2 Bank.idr -o bank && ./build/exec/bank < transactions.txt` prints what the
Haskell program prints for the same input. Keep the same functions (`apply`, `run`,
`parseTx`, `report`) and the same types as far as Idris allows.

One deliberate difference: the Haskell version crashes when the amount is not a
number. In the Idris version a line whose amount is not a decimal integer is skipped,
like any other malformed line. A negative amount such as `-5` is a number and is
reported as a bad amount.

`transactions.txt` is a sample input. The program reads standard input until end of
file, however long the input is.
