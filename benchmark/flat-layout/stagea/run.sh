#!/usr/bin/env bash
# Stage A of the RefC flat layout (raw fields): the programs of this
# directory, built by a compiler with and without `--directive
# refc-no-raw-fields`, and by a base compiler if one is given, checked to
# print the same, and measured (instructions:u, median of RUNS).
#
# Usage: run.sh NEW_IDRIS2 [BASE_IDRIS2]   (IDRIS2_PREFIX / BASE_PREFIX for
# their libraries; RUNS=3, FAST=1 for the fast inputs)
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
NEW=$1
BASE=${2:-}
RUNS=${RUNS:-3}
WORK="$here/build"
export TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR"
bench="$here/../../benchmarks"
# program  packages  input  fast input
progs="particles:contrib:$here/particles.in:$here/particles_fast.in
events:contrib:$here/events.in:$here/events_fast.in
nbody::$here/nbody.in:$here/nbody_fast.in
mandel::$here/mandel.in:$here/mandel_fast.in
mergeA::$bench/mergeInt/mergeInt.in:$bench/mergeInt/mergeInt_fast.in
mergeB::$bench/mergeInt/mergeInt.in:$bench/mergeInt/mergeInt_fast.in
treeA::$bench/treeInt/treeInt.in:$bench/treeInt/treeInt_fast.in
treeB::$bench/treeInt/treeInt.in:$bench/treeInt/treeInt_fast.in"

build() { # variant compiler prefix directive prog pkgs
  local v=$1 c=$2 pre=$3 dir=$4 p=$5 pk=$6
  local d="$WORK/$v"
  mkdir -p "$d"
  cp "$here/$p.idr" "$d/"
  (cd "$d" && IDRIS2_PREFIX=$pre "$c" --cg refc ${pk:+-p $pk} ${dir:+--directive $dir} -o "$p" "$p.idr" > /dev/null)
}

median() { sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}'; }

measure() { # exe input
  for r in $(seq 1 "$RUNS"); do
    perf stat -x, -e instructions:u -o "$WORK/perf.txt" "$1" < "$2" > /dev/null
    awk -F, '$3 ~ /^instructions/ {print $1}' "$WORK/perf.txt"
  done | median
}

printf "program\traw\tnoraw\tbase\tnoraw/raw\tbase/raw\n"
echo "$progs" | while IFS=: read -r p pk full fast; do
  in=$full; [ "${FAST:-}" = 1 ] && in=$fast
  build raw "$NEW" "${IDRIS2_PREFIX:-}" "" "$p" "$pk"
  build noraw "$NEW" "${IDRIS2_PREFIX:-}" refc-no-raw-fields "$p" "$pk"
  [ -n "$BASE" ] && build base "$BASE" "${BASE_PREFIX:-}" "" "$p" "$pk"
  ref="$("$WORK/raw/build/exec/$p" < "$in")"
  for v in noraw ${BASE:+base}; do
    out="$("$WORK/$v/build/exec/$p" < "$in")"
    [ "$out" = "$ref" ] || { echo "MISMATCH $p $v: $out / $ref" >&2; exit 1; }
  done
  r=$(measure "$WORK/raw/build/exec/$p" "$in")
  n=$(measure "$WORK/noraw/build/exec/$p" "$in")
  b=-; [ -n "$BASE" ] && b=$(measure "$WORK/base/build/exec/$p" "$in")
  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$p" "$r" "$n" "$b" \
    "$(awk -v a="$n" -v b="$r" 'BEGIN {printf "%.2f", a/b}')" \
    "$( [ "$b" = - ] && echo - || awk -v a="$b" -v b="$r" 'BEGIN {printf "%.2f", a/b}')"
done
