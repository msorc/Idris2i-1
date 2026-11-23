`Report.idr` works but is far too slow: `./build/exec/report 1200` takes several
seconds and I need `report 20000`. Find out why and make it fast.

The output must stay exactly the same for every limit. Keep it a single file built with
`idris2 Report.idr -o report`, pure Idris (no FFI). Tell me briefly what was slow.
