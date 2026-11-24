#!/bin/sh
# Measure the Idris HTTP server against Go's net/http with a closed-loop
# load generator.  For each server and setting: requests per second, server
# CPU seconds per 100k requests, server user-space instructions per request
# (perf stat), peak RSS; then the resident memory with 100 and 5,000 idle
# persistent connections.  With the http-tls library (built when OpenSSL 3
# is there; HTTPS=0 skips it), the same over HTTPS on persistent
# connections, with a throwaway ECDSA P-256 certificate, and HTTP/2 over
# TLS (net/http as the load generator).  HTTP/2 over h2c is measured with
# the client of the library as the load generator (H2Load.idr).
#
#   benchmark/http/run.sh            (from the root of the repository, after make)
#
# Builds into build/bench.  The machine may be busy: compare CPU time and
# instructions per request rather than requests per second.
set -e
root=$(pwd)
out="$root/build/bench"
here="$root/benchmark/http"
conns=${CONNS:-64}
# the libraries of the build tree
export IDRIS2I_1_PREFIX=${IDRIS2I_1_PREFIX:-$root/build/env}
dur=${DURATION:-10s}
mkdir -p "$out/idris"
(cd "$here" && go build -o "$out/loadgen" ./loadgen && go build -o "$out/goserver" ./goserver)
cp "$here/idris/Main.idr" "$here/idris/Routes.idr" "$here/idris/Https.idr" "$here/idris/H2Load.idr" "$out/idris/"
(cd "$out/idris" && "$root/build/exec/idris2i-1" -p contrib -p network -p http -o server Main.idr)
(cd "$out/idris" && "$root/build/exec/idris2i-1" -p contrib -p network -p http -o h2load H2Load.idr)
https=${HTTPS:-1}
if [ "$https" = 1 ] && ls -d "$IDRIS2I_1_PREFIX"/idris2i-1-*/http-tls-* > /dev/null 2>&1 && command -v openssl > /dev/null; then
  (cd "$out/idris" && "$root/build/exec/idris2i-1" -p contrib -p network -p http -p tls -p http-tls -o https-server Https.idr)
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$out/key.pem" \
    -out "$out/cert.pem" -days 2 -subj /CN=localhost -addext subjectAltName=IP:127.0.0.1 2> /dev/null
else
  https=0
fi

cpu() { awk '{print $14 + $15}' "/proc/$1/stat"; }
hwm() { awk '/VmHWM/ {print $2}' "/proc/$1/status"; }
rss() { awk '/VmRSS/ {print $2}' "/proc/$1/status"; }
tck=$(getconf CLK_TCK)
port=18080

# start <label> <env> <command...>: starts the server, sets $pid
start() {
  label=$1; shift
  port=$((port + 1))
  env PORT=$port "$@" $port > /dev/null 2>&1 &
  pid=$!
  sleep 0.5
}

load() { # load <label> <loadgen args...>
  label=$1; shift
  gen "$label" "$out/loadgen" -addr 127.0.0.1:$port -conns $conns -duration $dur "$@"
}

gen() { # gen <label> <load generator and its arguments...>
  label=$1; shift
  c0=$(cpu $pid)
  perf stat -x, -e instructions:u -p $pid -o "$out/perf.txt" &
  ppid=$!
  sleep 0.2
  res=$("$@")
  kill -INT $ppid; wait $ppid 2>/dev/null || true
  c1=$(cpu $pid)
  n=$(echo "$res" | awk '{print $2}')
  rps=$(echo "$res" | awk '{print $6}')
  ins=$(awk -F, '/instructions/ {print $1}' "$out/perf.txt")
  echo "$label | $rps | $(echo "scale=2; ($c1 - $c0) / $tck * 100000 / $n" | bc) | $(echo "$ins / $n" | bc) | $(hwm $pid)"
}

idle() { # idle <label> <n>
  "$out/loadgen" -addr 127.0.0.1:$port -idle $2 -hold 3s > /dev/null &
  lpid=$!
  sleep 2.5
  r=$(rss $pid)
  wait $lpid
  echo "$1 | $2 idle | RSS $r kB"
}

echo "server | req/s | CPU s/100k req | instr/req | peak RSS kB"
for w in 1 4; do
  start idris env IDRIS2I_1_WORKERS=$w "$out/idris/build/exec/server"
  load "idris W=$w hello" -path /hello
  load "idris W=$w json" -method POST -path /json -body "$here/body.json"
  kill $pid; wait $pid 2>/dev/null || true
done
for p in 1 4; do
  start go env GOMAXPROCS=$p "$out/goserver"
  load "go P=$p hello" -path /hello
  load "go P=$p json" -method POST -path /json -body "$here/body.json"
  kill $pid; wait $pid 2>/dev/null || true
done
# HTTP/2 over h2c (prior knowledge), with the client of the library as the
# load generator (Go's net/http has no h2c without golang.org/x/net):
# 1 connection with 64 streams, and 64 connections with 1 stream each
secs=${dur%s}
h2gen() { IDRIS2I_1_WORKERS=4 "$out/idris/build/exec/h2load" $port "$@"; }
for w in 1 4; do
  start idris env IDRIS2I_1_WORKERS=$w "$out/idris/build/exec/server"
  gen "idris W=$w h2c hello 1x64" h2gen 1 64 $secs /hello
  gen "idris W=$w h2c json 1x64" h2gen 1 64 $secs /json "$here/body.json"
  gen "idris W=$w h2c hello 64x1" h2gen 64 1 $secs /hello
  gen "idris W=$w h2c json 64x1" h2gen 64 1 $secs /json "$here/body.json"
  kill $pid; wait $pid 2>/dev/null || true
done
if [ "$https" = 1 ]; then
  # startTLS <env> <command>: as start, with the certificate and the key
  # after the port
  startTLS() {
    port=$((port + 1))
    env "$@" $port "$out/cert.pem" "$out/key.pem" > /dev/null 2>&1 &
    pid=$!
    sleep 0.5
  }
  for w in 1 4; do
    startTLS IDRIS2I_1_WORKERS=$w "$out/idris/build/exec/https-server"
    load "idris W=$w https hello" -tls -path /hello
    load "idris W=$w https json" -tls -method POST -path /json -body "$here/body.json"
    gen "idris W=$w h2 hello 1x64" "$out/loadgen" -addr 127.0.0.1:$port -h2 -conns 1 -streams 64 -duration $dur -path /hello
    gen "idris W=$w h2 json 1x64" "$out/loadgen" -addr 127.0.0.1:$port -h2 -conns 1 -streams 64 -duration $dur -method POST -path /json -body "$here/body.json"
    gen "idris W=$w h2 hello 64x1" "$out/loadgen" -addr 127.0.0.1:$port -h2 -conns 64 -streams 1 -duration $dur -path /hello
    gen "idris W=$w h2 json 64x1" "$out/loadgen" -addr 127.0.0.1:$port -h2 -conns 64 -streams 1 -duration $dur -method POST -path /json -body "$here/body.json"
    kill $pid; wait $pid 2>/dev/null || true
  done
  for p in 1 4; do
    start go env GOMAXPROCS=$p CERT="$out/cert.pem" KEY="$out/key.pem" "$out/goserver"
    load "go P=$p https hello" -tls -path /hello
    load "go P=$p https json" -tls -method POST -path /json -body "$here/body.json"
    gen "go P=$p h2 hello 1x64" "$out/loadgen" -addr 127.0.0.1:$port -h2 -conns 1 -streams 64 -duration $dur -path /hello
    gen "go P=$p h2 json 1x64" "$out/loadgen" -addr 127.0.0.1:$port -h2 -conns 1 -streams 64 -duration $dur -method POST -path /json -body "$here/body.json"
    gen "go P=$p h2 hello 64x1" "$out/loadgen" -addr 127.0.0.1:$port -h2 -conns 64 -streams 1 -duration $dur -path /hello
    gen "go P=$p h2 json 64x1" "$out/loadgen" -addr 127.0.0.1:$port -h2 -conns 64 -streams 1 -duration $dur -method POST -path /json -body "$here/body.json"
    kill $pid; wait $pid 2>/dev/null || true
  done
fi
ulimit -n 20000 2>/dev/null || true
for n in 100 5000; do
  start idris env IDRIS2I_1_WORKERS=4 "$out/idris/build/exec/server"
  r0=$(rss $pid)
  idle "idris (RSS at start $r0 kB)" $n
  kill $pid; wait $pid 2>/dev/null || true
  start go env GOMAXPROCS=4 "$out/goserver"
  r0=$(rss $pid)
  idle "go (RSS at start $r0 kB)" $n
  kill $pid; wait $pid 2>/dev/null || true
done
