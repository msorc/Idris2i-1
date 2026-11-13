#!/usr/bin/env bash
# Build the benchmarks with the RefC backend and measure them: instructions
# and cycles (user space, from `perf stat`), wall time and peak RSS.
#
# Instructions are the primary metric: wall time swings by 50% or more when
# anything else runs on the machine (a compile, say).
#
# Usage: refc-perf.sh [OPTION]... [BENCHMARK]...
#   -c IDRIS2   the compiler (default: idris2 on the PATH)
#   -o FILE     append the results to FILE (default: refc-perf.csv)
#   -l LABEL    the label of this configuration in the CSV (default: refc)
#   -d DIR      the work directory for the builds (default: ./refc-perf-work)
#   -D DIRECT   pass `--directive DIRECT` to the compiler (repeatable)
#   -X OPTION   pass OPTION to the compiler (repeatable), e.g. -X --spec-interfaces
#   -n RUNS     runs of each benchmark (default: 1); every run is a new
#               process with its own stdin (perf stat -r would reuse stdin)
#   -f          the fast inputs (BENCHMARK_fast.in)
#   -B          do not build, reuse the executables of the work directory
#   -e VAR=VAL  set an environment variable for the runs (repeatable)
#
# The CSV has the columns
#   label,benchmark,run,instructions,cycles,elapsed_s,maxrss_kb,status
#
# Set IDRIS2_PREFIX (and IDRIS2_CFLAGS) as for any build.

set -u

here="$(cd "$(dirname "$0")" && pwd)"
IDRIS2=idris2
OUT=refc-perf.csv
LABEL=refc
WORK="$PWD/refc-perf-work"
DIRECTIVES=()
EXTRA=()
RUNS=1
FAST=false
BUILD=true
ENVS=()

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

while getopts ":c:o:l:d:D:X:n:fBe:h" opt; do
  case "$opt" in
    c) IDRIS2="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    l) LABEL="$OPTARG" ;;
    d) WORK="$OPTARG" ;;
    D) DIRECTIVES+=(--directive "$OPTARG") ;;
    X) EXTRA+=("$OPTARG") ;;
    n) RUNS="$OPTARG" ;;
    f) FAST=true ;;
    B) BUILD=false ;;
    e) ENVS+=("$OPTARG") ;;
    h) usage 0 ;;
    :) echo "option -$OPTARG needs an argument" >&2; usage ;;
    \?) echo "unknown option -$OPTARG" >&2; usage ;;
  esac
done
shift $((OPTIND - 1))

case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
case "$WORK" in /*) ;; *) WORK="$PWD/$WORK" ;; esac

if [ $# -gt 0 ]; then
  BENCHES=("$@")
else
  BENCHES=()
  for d in "$here"/benchmarks/*/; do
    BENCHES+=("$(basename "$d")")
  done
fi

if ! command -v perf >/dev/null 2>&1; then
  echo "refc-perf.sh needs perf" >&2
  exit 1
fi

mkdir -p "$WORK"
MAXRSS="$WORK/maxrss"
if [ ! -x "$MAXRSS" ] || [ "$here/maxrss.c" -nt "$MAXRSS" ]; then
  ${CC:-cc} -O2 -o "$MAXRSS" "$here/maxrss.c" || exit 1
fi

[ -s "$OUT" ] ||
  echo "label,benchmark,run,instructions,cycles,elapsed_s,maxrss_kb,status" > "$OUT"

for b in "${BENCHES[@]}"; do
  src="$here/benchmarks/$b"
  exe="$WORK/$LABEL/$b/exec/$b"
  if [ ! -f "$src/$b.idr" ]; then
    echo "no benchmark $b" >&2
    continue
  fi
  if $BUILD; then
    echo "building $b ($LABEL)" >&2
    rm -f "$exe"
    (cd "$src" &&
       "$IDRIS2" --cg refc "${DIRECTIVES[@]}" "${EXTRA[@]}" \
         --build-dir "$WORK/$LABEL/$b/build" \
         --output-dir "$WORK/$LABEL/$b/exec" \
         -o "$b" "$b.idr") >&2
    # (idris2 exits with 0 even when the C compiler fails)
    if [ ! -x "$exe" ]; then
      echo "building $b failed" >&2
      continue
    fi
  fi
  if $FAST; then input="$src/${b}_fast.in"; else input="$src/$b.in"; fi
  [ -f "$input" ] || input=/dev/null
  for run in $(seq 1 "$RUNS"); do
    perfout="$WORK/perf.$$"
    rssout="$WORK/rss.$$"
    rm -f "$perfout" "$rssout"
    (cd "$src" &&
       env "${ENVS[@]}" perf stat -x, -e instructions:u,cycles:u -o "$perfout" -- \
         "$MAXRSS" "$rssout" -- "$exe" < "$input" > /dev/null)
    status=$?
    instr=$(awk -F, '$3 ~ /^instructions/ {print $1}' "$perfout")
    cycles=$(awk -F, '$3 ~ /^cycles/ {print $1}' "$perfout")
    IFS=, read -r rss elapsed < "$rssout"
    echo "$LABEL,$b,$run,$instr,$cycles,$elapsed,$rss,$status" | tee -a "$OUT"
  done
done
