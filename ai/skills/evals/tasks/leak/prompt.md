`Hub.idr` is the core of a chat server, here driven by a load generator instead of the
network. Its memory grows with the number of rounds: `./build/exec/hub 400000` peaks
near 230 MB, and the real server has to stay up for weeks. Find out what holds the
memory and fix it.

`hub 2000000` must peak under 16 MB (I measure with `/usr/bin/time -f %M`), and
nothing may be left allocated when the program exits. The output must stay exactly the
same for every number of rounds. Keep it a single file built with
`idris2i-1 Hub.idr -o hub` (the default C back end), pure Idris2i-1 (no FFI). Tell me briefly
what was holding the memory.
