#!/bin/sh
# Measure the WebSocket echo server of the http library: for 64-byte and
# 16 KiB messages, 1 and 64 connections, 1 and 4 workers, the user-space
# instructions, CPU time and system calls of the server per message round
# trip, and its resident memory per idle connection with 5,000 of them.
#
#   benchmark/websocket/run.sh     (from the root of the repository, after make)
#
# SIZES, CONNS and WORKERS choose the settings (all by default), ECHO=0
# skips the echoes and MEMORY=0 the measure of memory, and SERVER_MODE=channel runs the variant of
# the server that sends from a writer thread fed by a channel.  GO=1
# measures an echo server written with gorilla/websocket instead (built from
# the Go module cache, without downloading; GOMAXPROCS is the number of
# workers).
#
# Each setting runs the server twice under `perf stat` (and twice under
# `strace -c`): once with the messages and once with the same connections
# and no message, and the difference is divided by the number of messages,
# so that starting up and connecting are not counted.  The load generator
# is written with the client of the library.  The machine may be busy:
# compare instructions and system calls rather than times.
set -e
root=$(pwd)
out="$root/build/bench-ws"
here="$root/benchmark/websocket"
export IDRIS2_PREFIX=${IDRIS2_PREFIX:-$root/build/env}
mkdir -p "$out"
cp "$here/Server.idr" "$here/Load.idr" "$out/"
(cd "$out" && "$root/build/exec/idris2" -p contrib -p network -p http -o server Server.idr \
           && "$root/build/exec/idris2" -p contrib -p network -p http -o load Load.idr)
server="$out/build/exec/server"
if [ "${GO:-0}" = 1 ]; then
  # the same echo with gorilla/websocket (from the module cache: no download)
  (cd "$here/goserver" && GOFLAGS=-mod=mod GOPROXY=off GOSUMDB=off go build -o "$out/goserver" .)
  server="$out/goserver"
fi
load="$out/build/exec/load"
port=19100

# run <workers> <wrapper...>: the server under a wrapper, with the load
# given in $LOAD; waits for the end of both.
run() {
  w=$1; shift
  port=$((port + 1))
  rm -f "$out/ready"
  IDRIS2_WORKERS=$w GOMAXPROCS=$w "$@" "$server" $port $SERVER_MODE > "$out/ready" 2>/dev/null &
  spid=$!
  i=0; while ! grep -q listening "$out/ready" 2>/dev/null; do sleep 0.05; i=$((i+1)); [ $i -gt 200 ] && break; done
  # (the load generator stops the server at the end)
  IDRIS2_WORKERS=4 "$load" $port $LOAD > "$out/load.txt"
  wait $spid
}

perfrun() { # perfrun <workers>: instructions and CPU ms of the server
  run $1 perf stat -x, -e instructions:u -e task-clock -o "$out/perf.txt" --
  ins=$(awk -F, '/instructions/ {print $1}' "$out/perf.txt")
  ms=$(awk -F, '/task-clock/ {print $1}' "$out/perf.txt")
}

straced() { # straced <workers>: system calls of the server
  run $1 strace -f -c -o "$out/strace.txt"
  calls=$(awk '/total/ {print $4}' "$out/strace.txt")
}

if [ "${ECHO:-1}" != 0 ]; then
echo "workers | conns | size | instructions/msg | CPU us/msg | syscalls/msg"
for w in ${WORKERS:-1 4}; do
  for c in ${CONNS:-1 64}; do
    for s in ${SIZES:-64 16384}; do
      if [ $s = 64 ]; then total=100000; else total=20000; fi
      m=$((total / c))
      n=$((m * c))
      LOAD="echo $c $m $s"; perfrun $w; i1=$ins; t1=$ms; straced $w; s1=$calls
      LOAD="echo $c 0 $s"; perfrun $w; i0=$ins; t0=$ms; straced $w; s0=$calls
      echo "$w | $c | $s | $(( (i1 - i0) / n )) | $(echo "scale=2; ($t1 - $t0) * 1000 / $n" | bc) | $(echo "scale=2; ($s1 - $s0) / $n" | bc)"
    done
  done
done
fi

# memory per idle connection
[ "${MEMORY:-1}" = 0 ] && exit 0
for w in ${WORKERS:-1 4}; do
  port=$((port + 1))
  rm -f "$out/ready"
  IDRIS2_WORKERS=$w GOMAXPROCS=$w "$server" $port > "$out/ready" 2>/dev/null &
  spid=$!
  i=0; while ! grep -q listening "$out/ready" 2>/dev/null; do sleep 0.05; i=$((i+1)); [ $i -gt 200 ] && break; done
  r0=$(awk '/VmRSS/ {print $2}' /proc/$spid/status)
  rm -f "$out/idle.txt"
  "$load" $port idle 5000 8 > "$out/idle.txt" &
  lpid=$!
  i=0; while ! grep -q open "$out/idle.txt" 2>/dev/null; do sleep 0.1; i=$((i+1)); [ $i -gt 600 ] && break; done
  sleep 1
  r1=$(awk '/VmRSS/ {print $2}' /proc/$spid/status)
  wait $lpid
  wait $spid
  echo "workers $w: $(( (r1 - r0) * 1024 / 5000 )) bytes per idle connection (RSS $r0 kB -> $r1 kB)"
done
