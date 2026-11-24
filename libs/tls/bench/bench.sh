#!/bin/sh
# Measure the tls library with perf stat: the CPU time and instructions of
# the server process for n handshakes (ECDSA P-256 and RSA-2048 keys), and
# of the sending and receiving processes for a bulk transfer through TLS and
# through a plain socket, with 1 and 4 workers.
#
# Usage: IDRIS2I_1=<idris2i-1> sh bench.sh [handshakes] [MB]   (in this directory,
# with the tls library built or installed for the compiler)
set -e
n=${1:-2000}
mb=${2:-512}
idris2i_1=${IDRIS2I_1:-idris2i-1}
here=$(pwd)
work=${TMPDIR:-/tmp}/tls-bench.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cd "$work"
. "$here/../../../tests/tls/gencerts.sh"
cp "$here/Bench.idr" .
"$idris2i_1" -p network -p tls -o bench Bench.idr > build.log || { cat build.log; exit 1; }
bench=./build/exec/bench

stat() { # label, command...
  label=$1; shift
  f="$work/stat.$(echo "$label" | tr -c 'a-z0-9' _)"
  perf stat -x, -e instructions:u,task-clock "$@" 2> "$f" > /dev/null
  ins=$(grep instructions "$f" | cut -d, -f1)
  ms=$(grep task-clock "$f" | cut -d, -f1)
  echo "$label,$ins,$ms"
}

waitport() { while [ ! -s "$work/port" ]; do sleep 0.05; done; cat "$work/port"; }

echo "what,workers,instructions,task-clock ms"
for w in 1 4; do
  for key in server rsa; do
    rm -f "$work/port"
    IDRIS2I_1_WORKERS=$w stat "handshakes $n server $key,$w" $bench hs-server "$certs" $key "$work/port" $n &
    p=$(waitport)
    IDRIS2I_1_WORKERS=$w stat "handshakes $n client $key,$w" $bench hs-client "$certs" $p $n 16
    wait
  done
  for kind in tls plain; do
    rm -f "$work/port"
    IDRIS2I_1_WORKERS=$w stat "bulk $mb MB send $kind,$w" $bench bulk-server $kind "$certs" "$work/port" $mb &
    p=$(waitport)
    IDRIS2I_1_WORKERS=$w stat "bulk $mb MB recv $kind,$w" $bench bulk-client $kind "$certs" $p $mb
    wait
  done
done
