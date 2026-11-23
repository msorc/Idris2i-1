#!/usr/bin/env bash
# Measure what type checking costs: run a compiler on a corpus of Idris 2
# sources in a few scenarios (a clean build, a rebuild after an edit, ...),
# and append to a CSV the instructions and cycles (user space, from
# `perf stat`, child processes included), the peak RSS (of the largest
# process) and the wall time of each.
#
# Instructions and peak RSS are the metrics to compare: wall time swings by
# 50% or more when anything else runs on the machine.
#
# Usage: tc-perf.sh [OPTION]... [CORPUS]...
#   -c IDRIS2   the compiler (default: idris2 on the PATH)
#   -o FILE     append the results to FILE (default: tc-perf.csv)
#   -l LABEL    the label of this compiler in the CSV (default: idris2)
#   -d DIR      the work directory (default: ./tc-perf-work)
#   -r TREE     the Idris 2 source tree to take the corpora from (default:
#               the tree this script is in)
#   -j N        the processes of the scenario clean-jN (default: 6)
#   -n RUNS     runs of each scenario (default: 1)
#   -s LIST     the scenarios, separated by commas (default: all, in this
#               order: clean-j1,noop,leaf,comment,iface,clean-jN)
#   -X OPTION   pass OPTION to the compiler (repeatable), e.g.
#               -X --timing-summary
#
# The corpora (default: compiler base contrib perf):
#   compiler    the compiler itself (idris2.ipkg: the modules of the compiler
#               executable)
#   base        libs/base
#   contrib     libs/contrib
#   perf        each of the single-file tests of tests/idris2/perf, alone
#               (only the clean-j1 scenario)
#
# The scenarios:
#   clean-j1    build everything, one process (IDRIS2_BUILD_JOBS=1)
#   noop        build again, nothing changed
#   leaf        build again after touching a module that no module imports
#   comment     build again after adding a comment to a module that most
#               modules import (its interface does not change)
#   iface       build again after adding an exported definition to that
#               module (its interface changes)
#   clean-jN    build everything, N processes (IDRIS2_BUILD_JOBS=N)
#
# Each corpus is copied to the work directory and type checked there with
# `--typecheck` (`--check` for perf), so that what is built in the source
# tree does not matter. The libraries that it needs are built by the
# compiler first (not measured), in WORK/LABEL/prefix-*, and kept for the
# next runs of the same compiler (they are built again when its version
# changes).
#
# The CSV has the columns
#   label,corpus,scenario,run,modules_built,instructions,cycles,elapsed_s,maxrss_kb,status
# where modules_built counts the "Building" lines of the output. The output
# of each run is kept in WORK/LABEL/logs (with -X --timing-summary, the
# profile: see sum-profile.sh).

set -u

here="$(cd "$(dirname "$0")" && pwd)"
TREE="$(cd "$here/../.." && pwd)"
IDRIS2=idris2
OUT=tc-perf.csv
LABEL=idris2
WORK="$PWD/tc-perf-work"
JOBS=6
RUNS=1
SCENARIOS=clean-j1,noop,leaf,comment,iface,clean-jN
EXTRA=()

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

while getopts ":c:o:l:d:r:j:n:s:X:h" opt; do
  case "$opt" in
    c) IDRIS2="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    l) LABEL="$OPTARG" ;;
    d) WORK="$OPTARG" ;;
    r) TREE="$OPTARG" ;;
    j) JOBS="$OPTARG" ;;
    n) RUNS="$OPTARG" ;;
    s) SCENARIOS="$OPTARG" ;;
    X) EXTRA+=("$OPTARG") ;;
    h) usage 0 ;;
    :) echo "option -$OPTARG needs an argument" >&2; usage ;;
    \?) echo "unknown option -$OPTARG" >&2; usage ;;
  esac
done
shift $((OPTIND - 1))

case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
case "$WORK" in /*) ;; *) WORK="$PWD/$WORK" ;; esac
case "$TREE" in /*) ;; *) TREE="$PWD/$TREE" ;; esac
if [ "${IDRIS2#*/}" != "$IDRIS2" ]; then
  IDRIS2="$(cd "$(dirname "$IDRIS2")" && pwd)/$(basename "$IDRIS2")"
fi

if [ $# -gt 0 ]; then CORPORA=("$@"); else CORPORA=(compiler base contrib perf); fi
IFS=, read -r -a SCEN <<< "$SCENARIOS"

if ! command -v perf >/dev/null 2>&1; then
  echo "tc-perf.sh needs perf" >&2
  exit 1
fi

# The leaf module, and the module near the root, of each corpus
leafOf() {
  case "$1" in
    compiler) echo src/Idris/Driver.idr ;;
    base) echo Data/List/Views.idr ;;
    contrib) echo Text/Parser/Expression.idr ;;
  esac
}
rootOf() {
  case "$1" in
    compiler) echo src/Core/Name.idr ;;
    base) echo Data/Nat.idr ;;
    contrib) echo Text/Lexer.idr ;;
  esac
}

mkdir -p "$WORK/$LABEL/logs"
MAXRSS="$WORK/maxrss"
if [ ! -x "$MAXRSS" ] || [ "$here/../maxrss.c" -nt "$MAXRSS" ]; then
  ${CC:-cc} -O2 -o "$MAXRSS" "$here/../maxrss.c" || exit 1
fi

[ -s "$OUT" ] ||
  echo "label,corpus,scenario,run,modules_built,instructions,cycles,elapsed_s,maxrss_kb,status" > "$OUT"

# A clean environment for the compiler: only the libraries of PREFIX
clean_env() {
  env -u IDRIS2_PATH -u IDRIS2_PACKAGE_PATH -u IDRIS2_LIBS -u IDRIS2_DATA \
      -u IDRIS2_BUILD_JOBS -u IDRIS2_CG "$@"
}

# Build and install the libraries a corpus needs with the compiler, in
# stages: prefix-prelude (for base), prefix-base (for contrib), prefix-full
# (for the compiler and perf). Not measured.
version="$("$IDRIS2" --version 2>/dev/null)"
prepare_prefixes() {
  local stamp="$WORK/$LABEL/prefix.stamp"
  if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$version" ] &&
     [ -d "$WORK/$LABEL/prefix-full" ]; then
    return 0
  fi
  echo "building the libraries with $IDRIS2 ($version)" >&2
  local lw="$WORK/$LABEL/libsrc" p="$WORK/$LABEL/prefix"
  rm -rf "${WORK:?}/$LABEL"/prefix* "${lw:?}"
  mkdir -p "$lw" "$p"
  cp -a "$TREE/libs/prelude" "$TREE/libs/base" "$TREE/libs/linear" \
        "$TREE/libs/network" "$TREE/libs/contrib" "$lw/"
  local lib
  for lib in prelude base linear network contrib; do
    rm -rf "${lw:?}/$lib/build"
    (cd "$lw/$lib" &&
       clean_env IDRIS2_PREFIX="$p" IDRIS2_BUILD_JOBS=6 \
         "$IDRIS2" --install "$lib.ipkg") > "$WORK/$LABEL/logs/install-$lib.log" 2>&1 ||
      { echo "building $lib failed, see $WORK/$LABEL/logs/install-$lib.log" >&2; exit 1; }
    case "$lib" in
      prelude) cp -a "$p" "$WORK/$LABEL/prefix-prelude" ;;
      base) cp -a "$p" "$WORK/$LABEL/prefix-base" ;;
    esac
  done
  mv "$p" "$WORK/$LABEL/prefix-full"
  echo "$version" > "$stamp"
}

prefixOf() {
  case "$1" in
    base) echo "$WORK/$LABEL/prefix-prelude" ;;
    contrib) echo "$WORK/$LABEL/prefix-base" ;;
    *) echo "$WORK/$LABEL/prefix-full" ;;
  esac
}

# Copy a corpus to DIR (its build directory removed)
copy_corpus() {
  local corpus="$1" dir="$2"
  rm -rf "${dir:?}"
  mkdir -p "$dir"
  case "$corpus" in
    compiler)
      cp -a "$TREE/src" "$TREE/idris2.ipkg" "$dir/"
      if [ ! -f "$dir/src/IdrisPaths.idr" ]; then
        echo "no src/IdrisPaths.idr in $TREE: run make there first" >&2
        exit 1
      fi ;;
    base|contrib) cp -a "$TREE/libs/$corpus/." "$dir/" ;;
    perf/*) cp -a "$TREE/tests/idris2/$corpus/." "$dir/" ;;
  esac
  rm -rf "${dir:?}/build"
}

ipkgOf() {
  case "$1" in
    compiler) echo idris2.ipkg ;;
    *) echo "$1.ipkg" ;;
  esac
}

# measure CORPUS SCENARIO RUN DIR PREFIX JOBS COMMAND...
measure() {
  local corpus="$1" scen="$2" run="$3" dir="$4" prefix="$5" jobs="$6"
  shift 6
  local tag; tag="$(echo "$corpus" | tr / -)-$scen-$run"
  local log="$WORK/$LABEL/logs/$tag.log"
  local perfout="$WORK/perf.$$" rssout="$WORK/rss.$$"
  rm -f "$perfout" "$rssout"
  (cd "$dir" &&
     clean_env IDRIS2_PREFIX="$prefix" IDRIS2_BUILD_JOBS="$jobs" \
       perf stat -x, -e instructions:u,cycles:u -o "$perfout" -- \
         "$MAXRSS" "$rssout" -- "$@" > "$log" 2>&1 < /dev/null)
  local status=$?
  local instr cycles rss elapsed built
  instr=$(awk -F, '$3 ~ /^instructions/ {print $1}' "$perfout")
  cycles=$(awk -F, '$3 ~ /^cycles/ {print $1}' "$perfout")
  IFS=, read -r rss elapsed < "$rssout"
  built=$(grep -cE '^ *[0-9]+/[0-9]+: Building ' "$log")
  echo "$LABEL,$corpus,$scen,$run,$built,$instr,$cycles,$elapsed,$rss,$status" | tee -a "$OUT"
}

prepare_prefixes

for corpus in "${CORPORA[@]}"; do
  if [ "$corpus" = perf ]; then
    for d in "$TREE"/tests/idris2/perf/*/; do
      srcs=("$d"*.idr)
      [ "${#srcs[@]}" -eq 1 ] || continue
      name="perf/$(basename "$d")"
      file="$(basename "${srcs[0]}")"
      dir="$WORK/$LABEL/corpus/$name"
      for run in $(seq 1 "$RUNS"); do
        copy_corpus "$name" "$dir"
        measure "$name" clean-j1 "$run" "$dir" "$(prefixOf perf)" 1 \
          "$IDRIS2" "${EXTRA[@]}" --check "$file"
      done
    done
    continue
  fi
  dir="$WORK/$LABEL/corpus/$corpus"
  ipkg="$(ipkgOf "$corpus")"
  prefix="$(prefixOf "$corpus")"
  leaf="$(leafOf "$corpus")"
  root="$(rootOf "$corpus")"
  for run in $(seq 1 "$RUNS"); do
    copy_corpus "$corpus" "$dir"
    orig="$WORK/$LABEL/root.orig"
    cp -p "$dir/$root" "$orig"
    built=false
    for scen in "${SCEN[@]}"; do
      jobs=1
      case "$scen" in
        clean-j1) rm -rf "${dir:?}/build" ;;
        clean-jN) rm -rf "${dir:?}/build"; jobs="$JOBS" ;;
        noop) ;;
        leaf) touch "$dir/$leaf" ;;
        comment) cp "$orig" "$dir/$root"
                 printf '\n-- tc-perf: a comment\n' >> "$dir/$root" ;;
        iface) cp "$orig" "$dir/$root"
               printf '\n-- tc-perf: an interface change\nexport\ntcPerfMarker : Nat\ntcPerfMarker = 0\n' >> "$dir/$root" ;;
        *) echo "unknown scenario $scen" >&2; continue ;;
      esac
      case "$scen" in
        clean-*) ;;
        *) if ! $built; then
             echo "scenario $scen needs a build first: skipped" >&2
             continue
           fi ;;
      esac
      measure "$corpus" "$scen" "$run" "$dir" "$prefix" "$jobs" \
        "$IDRIS2" "${EXTRA[@]}" --typecheck "$ipkg"
      built=true
      # back to the sources as they were, for the next scenarios
      case "$scen" in
        comment|iface)
          cp -p "$orig" "$dir/$root"
          touch "$dir/$root"
          (cd "$dir" && clean_env IDRIS2_PREFIX="$prefix" IDRIS2_BUILD_JOBS="$JOBS" \
             "$IDRIS2" --typecheck "$ipkg" > /dev/null 2>&1 < /dev/null) ;;
      esac
    done
  done
done
