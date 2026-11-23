`idris2 --check Prices.idr` takes about fifteen seconds on my machine for a file of
160 lines, and the file is going to grow to several hundred items. Find out why
checking is slow and change the file so that it checks fast and stays fast as items
are added.

The program must print exactly what it prints now (`expected.txt`). Keep it one file,
`Prices.idr`, with the same data. Tell me briefly what the cause was.
