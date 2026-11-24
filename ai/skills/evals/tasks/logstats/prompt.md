Write `logstats` in Idris2i-1: `idris2i-1 Logstats.idr -o logstats` (add `-p` flags in a
`build.sh` if you need packages; `sh build.sh` must then produce
`build/exec/logstats`).

`logstats FILE...` reads web-server logs. Each line is `METHOD PATH STATUS BYTES`,
for example `GET /index.html 200 5120`. Every file is processed in its own thread;
the threads send their results to the main thread over a channel, and the main thread
merges them and prints:

- for each status code, in ascending order: `STATUS COUNT BYTES` (number of lines with
  that status, and the sum of their bytes)
- `files N`: the number of files that could be read
- `bad lines M`: lines that are not four fields with a numeric status and byte count
  (empty lines are ignored and not counted)

A file that cannot be read is reported on standard error as `cannot read NAME` and
otherwise skipped; the exit status is 0 all the same. The byte totals can exceed
2^32.
