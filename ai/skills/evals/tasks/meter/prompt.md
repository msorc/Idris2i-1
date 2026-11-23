`Meter.idr` makes the nightly digest of our meter readings. It runs on a small box
where the cost is counted in instructions, and it is far over budget: I need
`./build/exec/meter 200000` to take at least 8 times fewer user-mode instructions than
it does now (I measure with `perf stat -e instructions:u`). Find out where the
instructions go and bring it under the budget.

The output must stay exactly the same for every number of readings. Keep it a single
file built with `idris2 Meter.idr -o meter` (the default C back end), pure Idris (no
FFI, no C compiler flags). Tell me briefly what was expensive, with the numbers you
measured.
