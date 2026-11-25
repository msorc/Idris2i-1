#!/usr/bin/env bash
# Measure the size and the speed of RefC executables: the compiler built by
# itself (stage 2), a hello world and some mid-size programs.
#
# Usage:
#   refc-size.sh build [OPTION]... OUT
#     Freeze the tree's prefix (build/env, dereferenced) and stage-1 compiler
#     (build/exec) in OUT, then build there with them:
#       OUT/stage2/exec/idris2i-1   the compiler built by the stage-1
#                                   compiler, with the runtime of the prefix
#       OUT/prog/<name>/exec/<name> hello, runtests (tests/tests.ipkg),
#                                   websocket_echo (tests/http)
#       OUT/bench/<label>/...       the benchmarks of refc-perf.sh (natOps
#                                   among them is the third mid-size program)
#     and print and append the sizes (see `sizes`) to the CSV.  The tree must
#     have been built: `make` and `make testenv`.
#   refc-size.sh sizes [-o CSV] OUT...
#     The size table of the binaries of each OUT, with the change from the
#     first OUT.  Columns (bytes): file, .text, .rodata, .eh_frame +
#     .eh_frame_hdr, .sframe, .data.rel.ro, .rela.dyn, .relr.dyn, .symtab +
#     .strtab, and the file after `strip` (of a copy).
#   refc-size.sh measure [OPTION]... OUT [OUT2]
#     Speed, alternating the configurations (A B A B ...): user-space
#     instructions and cycles of OUT/stage2 type-checking a fresh copy of
#     libs/prelude and of libs/base (IDRIS2I_1_BUILD_JOBS=1), and every
#     benchmark of refc-perf.sh.  Prints mean, min-max spread and the change of
#     OUT2 from OUT with the larger of the two spreads next to it.  Run it
#     under the machine lock (`sz-measure refc-size.sh measure ...`), alone.
#   refc-size.sh padding BINARY
#     Bytes of .text that are NOP instructions (alignment padding).
#
# Options of build:
#   -t TREE     the tree (default: the one this script is in)
#   -l LABEL    the name of the configuration (default: basename of OUT)
#   -C FLAGS    extra C flags for the generated code and the link, as
#               IDRIS2I_1_CFLAGS (after the -O2 of the compiler)
#   -L FLAGS    extra link flags, as IDRIS2I_1_LDFLAGS
#   -D DIRECT   pass `--directive DIRECT` to the compiler (repeatable)
#   -R FLAGS    rebuild the runtime (support/c, support/refc of the tree) with
#               these extra CFLAGS, into the frozen prefix of OUT
#   -p PREFIX   freeze this prefix instead of TREE/build/env
#   -S          no stage 2 (only the programs)
#   -F          the fixpoint check: OUT/stage2 compiles the compiler again with
#               IDRIS2I_1_CC=true (no C compile) and its C is compared with
#               the one of stage 2
#   -k          keep the TTC, C and object files of the stage-2 build
#   -o CSV      append the sizes to CSV (default: OUT/../refc-size.csv)
#   -j N        IDRIS2I_1_BUILD_JOBS and IDRIS2I_1_CC_JOBS (default: 12)
# OUT must not exist, or be a directory that an earlier `build` made (it is
# then emptied).  The C compiler is wrapped to log the wall time of every
# call: `OUT/times` gives the Idris and the C phase of the stage-2 build.
# CFLAGS, LDFLAGS, CPPFLAGS and IDRIS2I_1_{C,LD,CPP}FLAGS of the environment
# are ignored, so that nothing but -O2 and the options reaches the C compiler.
#
# Options of measure:
#   -n RUNS     rounds (default: 5); every round runs each configuration once
#   -o CSV      append the runs to CSV (default: OUT/../refc-speed.csv)
#   -w WHAT     compiler, bench or all (default: all)
#   -b BENCH    only this benchmark (repeatable)
#
# Examples (SZ is the scratch directory of the campaign):
#   refc-size.sh build -F $SZ/me/base                  # unchanged flags
#   refc-size.sh build -C '-falign-jumps=1' $SZ/me/aj  # a flag experiment
#   sz-measure refc-size.sh measure -n 5 $SZ/baseline $SZ/me/aj
#   refc-size.sh sizes $SZ/baseline $SZ/me/aj

set -u

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/$(basename "$0")"

usage() {
  sed -n '2,/^$/p' "$script" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

die() { echo "refc-size.sh: $*" >&2; exit 1; }

abspath() { case "$1" in /*) echo "$1" ;; *) echo "$PWD/$1" ;; esac; }

now() { date +%s.%N; }

NAME_VERSION=idris2i-1-0.1.0

# ---------------------------------------------------------------- sizes

# One CSV line (without the label) for a binary:
# name,file,text,rodata,eh_frame,sframe,data_rel_ro,rela_dyn,relr_dyn,symtab_strtab,
# stripped (bytes)
size_line() {
  local name="$1" bin="$2" tmp
  tmp="$(mktemp)"
  cp "$bin" "$tmp" && strip "$tmp"
  local file stripped
  file=$(stat -c %s "$bin")
  stripped=$(stat -c %s "$tmp")
  rm -f "$tmp"
  readelf -SW "$bin" | sed -n 's/^ *\[ *[0-9]*\] //p' | awk -v name="$name" -v file="$file" -v stripped="$stripped" '
    { s[$1] = strtonum("0x" $5) }
    END {
      printf "%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n", name, file, s[".text"], s[".rodata"],
        s[".eh_frame"] + s[".eh_frame_hdr"], s[".sframe"], s[".data.rel.ro"], s[".rela.dyn"],
        s[".relr.dyn"], s[".symtab"] + s[".strtab"], stripped
    }'
}

# The binaries of an OUT, as `name path` lines.
binaries() {
  local out="$1" b d
  [ -x "$out/stage2/exec/idris2i-1" ] && echo "stage2 $out/stage2/exec/idris2i-1"
  for b in hello runtests websocket_echo; do
    [ -x "$out/prog/$b/exec/$b" ] && echo "$b $out/prog/$b/exec/$b"
  done
  for d in "$out"/bench/*/*/; do
    b="$(basename "$d")"
    [ -x "$d/exec/$b" ] && echo "$b $d/exec/$b"
  done
}

SIZE_HEADER="label,binary,file,text,rodata,eh_frame,sframe,data_rel_ro,rela_dyn,relr_dyn,symtab_strtab,stripped"

# sizes [-o CSV] OUT...
do_sizes() {
  local csv="" opt
  OPTIND=1
  while getopts ":o:h" opt; do
    case "$opt" in
      o) csv="$(abspath "$OPTARG")" ;;
      h) usage 0 ;;
      *) usage ;;
    esac
  done
  shift $((OPTIND - 1))
  [ $# -ge 1 ] || usage
  local all
  all="$(mktemp)"
  local out label name bin line
  for out in "$@"; do
    out="$(abspath "$out")"
    label="$(cat "$out/label" 2>/dev/null || basename "$out")"
    while read -r name bin; do
      line="$label,$(size_line "$name" "$bin")"
      echo "$line" >> "$all"
      if [ -n "$csv" ]; then
        [ -s "$csv" ] || echo "$SIZE_HEADER" > "$csv"
        echo "$line" >> "$csv"
      fi
    done < <(binaries "$out")
  done
  # The table, and the change from the first label.
  awk -F, '
    BEGIN { split("file text rodata eh_frame sframe data_rel_ro rela_dyn relr_dyn symtab_strtab stripped", col, " ") }
    NR == 1 { first = $1 }
    { key = $1 SUBSEP $2; for (i = 3; i <= 12; i++) v[key, i] = $i
      if (!($1 in seenl)) { seenl[$1] = 1; labels[++nl] = $1 }
      if (!($2 in seenb)) { seenb[$2] = 1; bins[++nb] = $2 } }
    END {
      printf "%-16s %-15s", "label", "binary"
      for (i = 1; i <= 10; i++) printf " %11s", substr(col[i], 1, 11)
      printf "\n"
      for (b = 1; b <= nb; b++)
        for (l = 1; l <= nl; l++) {
          key = labels[l] SUBSEP bins[b]
          if (!((key, 3) in v)) continue
          printf "%-16s %-15s", labels[l], bins[b]
          for (i = 3; i <= 12; i++) printf " %11d", v[key, i]
          printf "\n"
          k0 = first SUBSEP bins[b]
          if (labels[l] != first && (k0, 3) in v) {
            printf "%-16s %-15s", "", "  change"
            for (i = 3; i <= 12; i++) {
              if (v[k0, i] == 0) { printf " %11s", "-"; continue }
              printf " %+10.2f%%", 100 * (v[key, i] - v[k0, i]) / v[k0, i]
            }
            printf "\n"
          }
        }
    }' "$all"
  rm -f "$all"
}

# ---------------------------------------------------------------- build

# A wrapper of the C compiler that logs `start end status kind` per call.
write_cc_wrapper() {
  local wrap="$1" log="$2" real
  real="$(command -v "${IDRIS2I_1_CC:-${CC:-cc}}")" || die "no C compiler"
  cat > "$wrap" <<EOF
#!/bin/sh
kind=link
for a in "\$@"; do
  case "\$a" in
    -c) kind=compile; break ;;
    -M|--version|-dumpmachine) kind=other; break ;;
  esac
done
s=\$(date +%s.%N)
"$real" "\$@"
r=\$?
echo "\$s \$(date +%s.%N) \$r \$kind" >> "$log"
exit \$r
EOF
  chmod +x "$wrap"
}

# The phases of a build from the log of the wrapper: the C phase goes from
# the first compile to the end of the link; the longest single compile.
phases() {
  local log="$1" start="$2" end="$3"
  awk -v start="$start" -v end="$end" '
    $4 == "compile" { if (cs == "" || $1 < cs) cs = $1; d = $2 - $1; if (d > mx) mx = d; n++ }
    $4 == "link" { le = $2 }
    END {
      if (cs == "") { printf "total %.1f s, no C compile\n", end - start; exit }
      if (le == "") le = end
      printf "total %.1f s, Idris %.1f s, C %.1f s (%d compiles, longest %.1f s, link ends at %.1f s)\n",
        end - start, cs - start, le - cs, n, mx, le - start
    }' "$log"
}

do_build() {
  local tree="$here/.." label="" cflags="" ldflags="" rtflags="" prefix=""
  local stage2=true fixpoint=false keep=false csv="" jobs=12 opt
  local directives=()
  OPTIND=1
  while getopts ":t:l:C:L:D:R:p:SFko:j:h" opt; do
    case "$opt" in
      t) tree="$OPTARG" ;;
      l) label="$OPTARG" ;;
      C) cflags="$OPTARG" ;;
      L) ldflags="$OPTARG" ;;
      D) directives+=(--directive "$OPTARG") ;;
      R) rtflags="$OPTARG" ;;
      p) prefix="$OPTARG" ;;
      S) stage2=false ;;
      F) fixpoint=true ;;
      k) keep=true ;;
      o) csv="$OPTARG" ;;
      j) jobs="$OPTARG" ;;
      h) usage 0 ;;
      :) die "option -$OPTARG needs an argument" ;;
      \?) die "unknown option -$OPTARG" ;;
    esac
  done
  shift $((OPTIND - 1))
  [ $# -eq 1 ] || usage
  local out
  out="$(abspath "$1")"
  tree="$(cd "$tree" && pwd)" || die "no tree $tree"
  [ -n "$label" ] || label="$(basename "$out")"
  [ -n "$prefix" ] || prefix="$tree/build/env"
  prefix="$(cd "$prefix" && pwd)" || die "no prefix $prefix"
  [ -n "$csv" ] || csv="$(dirname "$out")/refc-size.csv"
  csv="$(abspath "$csv")"
  [ -x "$tree/build/exec/idris2i-1_app/idris2i-1" ] || die "$tree has no stage-1 compiler (make)"
  [ -d "$prefix/$NAME_VERSION/prelude-0.1.0" ] || die "$prefix has no libraries (make testenv)"

  if [ -e "$out" ]; then
    [ -f "$out/label" ] || die "$out exists and was not made by refc-size.sh build"
    rm -rf "$out"
  fi
  mkdir -p "$out" || exit 1
  echo "$label" > "$out/label"

  # Only what the options say reaches the C compiler.
  unset CFLAGS LDFLAGS CPPFLAGS LDLIBS IDRIS2I_1_CFLAGS IDRIS2I_1_LDFLAGS \
        IDRIS2I_1_CPPFLAGS IDRIS2I_1_LDLIBS IDRIS2I_1_PATH IDRIS2I_1_DATA IDRIS2I_1_LIBS
  [ -n "$cflags" ] && export IDRIS2I_1_CFLAGS="$cflags"
  [ -n "$ldflags" ] && export IDRIS2I_1_LDFLAGS="$ldflags"
  export IDRIS2I_1_BUILD_JOBS="$jobs" IDRIS2I_1_CC_JOBS="$jobs"

  # The frozen prefix and stage-1 compiler.
  echo "freezing $prefix and $tree/build/exec in $out" >&2
  cp -rL "$prefix" "$out/prefix" || exit 1
  mkdir -p "$out/stage1" &&
    cp -a "$tree/build/exec/idris2i-1" "$tree/build/exec/idris2i-1_app" "$out/stage1/" || exit 1
  export IDRIS2I_1_PREFIX="$out/prefix"
  local idris1="$out/stage1/idris2i-1"
  # (the sources that `measure` type-checks)
  local lib
  for lib in prelude base; do
    mkdir -p "$out/libsrc" && cp -r "$tree/libs/$lib" "$out/libsrc/" &&
      rm -rf "$out/libsrc/$lib/build" || exit 1
  done

  if [ -n "$rtflags" ]; then
    echo "building the runtime with $rtflags" >&2
    mkdir -p "$out/runtime" &&
      cp -a "$tree/config.mk" "$tree/support" "$out/runtime/" &&
      { [ ! -f "$tree/custom.mk" ] || cp -a "$tree/custom.mk" "$out/runtime/"; } || exit 1
    (cd "$out/runtime/support" &&
       make -C c clean >/dev/null && make -C refc clean >/dev/null &&
       CFLAGS="$rtflags" make -C c install PREFIX="$out/prefix" IDRIS2I_1_VERSION=0.1.0 &&
       CFLAGS="$rtflags" make -C refc install PREFIX="$out/prefix" IDRIS2I_1_VERSION=0.1.0) \
       > "$out/runtime.log" 2>&1 || die "the runtime failed to build, see $out/runtime.log"
  fi

  local cclog="$out/cc.log"
  write_cc_wrapper "$out/cc" "$cclog"
  export IDRIS2I_1_CC="$out/cc"

  {
    echo "label=$label"
    echo "tree=$tree ($(git -C "$tree" log -1 --format='%h %s' 2>/dev/null))"
    echo "dirty=$(git -C "$tree" status --porcelain --untracked-files=no 2>/dev/null | wc -l) files"
    echo "prefix=$prefix (frozen in $out/prefix)"
    echo "stage1=$("$idris1" --version)"
    echo "IDRIS2I_1_CFLAGS=${IDRIS2I_1_CFLAGS:-}"
    echo "IDRIS2I_1_LDFLAGS=${IDRIS2I_1_LDFLAGS:-}"
    echo "runtime CFLAGS=$rtflags"
    echo "directives=${directives[*]:-}"
    echo "cc=$("$out/cc" --version | head -1)"
  } > "$out/config"
  cat "$out/config" >&2

  local fail=false
  if $stage2; then
    echo "building stage 2 (log: $out/stage2.log)" >&2
    : > "$cclog"
    local t0 t1
    t0=$(now)
    (cd "$tree" && "$idris1" "${directives[@]}" --build idris2i-1.ipkg --build-dir "$out/stage2") \
      > "$out/stage2.log" 2>&1
    t1=$(now)
    if [ -x "$out/stage2/exec/idris2i-1" ] && file "$out/stage2/exec/idris2i-1" | grep -q ELF; then
      echo "stage2: $(phases "$cclog" "$t0" "$t1")" | tee "$out/times" >&2
      # the command line of a unit, to see the flags
      grep -m1 -o 'if claim [0-9]*; then [^&]*' "$out/stage2/exec/idris2i-1.build.sh" \
        > "$out/unit-command" 2>/dev/null
      "$out/stage2/exec/idris2i-1" --version >&2
    else
      echo "stage 2 failed, see $out/stage2.log" >&2
      fail=true
    fi
    cp "$cclog" "$out/stage2.cc.log"

    if $fixpoint && ! $fail; then
      echo "fixpoint: stage 2 compiles the compiler with IDRIS2I_1_CC=true" >&2
      (cd "$tree" && IDRIS2I_1_CC=true "$out/stage2/exec/idris2i-1" "${directives[@]}" \
         --build idris2i-1.ipkg --build-dir "$out/stage3") > "$out/stage3.log" 2>&1
      if cmp "$out/stage2/exec/idris2i-1.c" "$out/stage3/exec/idris2i-1.c"; then
        echo "fixpoint: same C ($(stat -c %s "$out/stage2/exec/idris2i-1.c") bytes)" | tee -a "$out/times" >&2
      else
        echo "fixpoint: DIFFERENT C, see $out/stage3" | tee -a "$out/times" >&2
        keep=true
      fi
      $keep || rm -rf "$out/stage3"
    fi
    if ! $keep; then
      rm -rf "$out/stage2/ttc"
      rm -f "$out"/stage2/exec/idris2i-1.u*.o "$out"/stage2/exec/idris2i-1.u*.c \
            "$out/stage2/exec/idris2i-1.c"
    fi
  fi

  # The programs, with the stage-1 compiler.
  : > "$cclog"
  local p="$out/prog"
  mkdir -p "$p/hello/src" "$p/websocket_echo/src"
  printf 'module Main\n\nmain : IO ()\nmain = putStrLn "hello"\n' > "$p/hello/src/Main.idr"
  cp "$tree/tests/http/common/HttpTest.idr" "$tree/tests/http/common/WsTest.idr" \
     "$tree/tests/http/websocket_echo/Main.idr" "$p/websocket_echo/src/"
  build_prog() {
    local name="$1" dir="$2"; shift 2
    echo "building $name" >&2
    (cd "$dir" && "$idris1" "${directives[@]}" "$@" --build-dir "$p/$name/build" \
       --output-dir "$p/$name/exec") > "$p/$name.log" 2>&1
    [ -x "$p/$name/exec/$name" ] || { echo "$name failed, see $p/$name.log" >&2; fail=true; }
  }
  build_prog hello "$p/hello/src" -o hello Main.idr
  build_prog websocket_echo "$p/websocket_echo/src" -p contrib -p network -p http -o websocket_echo Main.idr
  build_prog runtests "$tree/tests" --build tests.ipkg
  echo "building the benchmarks" >&2
  local dflags=()
  local d
  for d in "${directives[@]}"; do [ "$d" = --directive ] || dflags+=(-D "$d"); done
  "$here/refc-perf.sh" -c "$idris1" -d "$out/bench" -l "$label" -n 0 \
      -o "$out/bench/build.csv" "${dflags[@]}" > "$out/bench.log" 2>&1
  ls "$out"/bench/"$label"/*/exec/* > /dev/null 2>&1 || { echo "benchmarks failed, see $out/bench.log" >&2; fail=true; }
  rm -rf "$out"/bench/"$label"/*/build "$out"/prog/*/build

  do_sizes -o "$csv" "$out"
  $fail && exit 1
  exit 0
}

# ---------------------------------------------------------------- measure

# perf stat of a command (in a directory, with input): prints `instr,cycles,s`
perf_run() {
  local dir="$1" input="$2"; shift 2
  local pf
  pf="$(mktemp)"
  local t0 t1
  t0=$(now)
  (cd "$dir" && perf stat -x, -e instructions:u,cycles:u -o "$pf" -- "$@" < "$input" > /dev/null 2>&1)
  local status=$?
  t1=$(now)
  local i c
  i=$(awk -F, '$3 ~ /^instructions/ {print $1}' "$pf")
  c=$(awk -F, '$3 ~ /^cycles/ {print $1}' "$pf")
  rm -f "$pf"
  awk -v i="$i" -v c="$c" -v t0="$t0" -v t1="$t1" -v s="$status" \
    'BEGIN { printf "%s,%s,%.3f,%d\n", i, c, t1 - t0, s }'
}

do_measure() {
  local runs=5 csv="" what=all opt
  local benches=()
  OPTIND=1
  while getopts ":n:o:w:b:h" opt; do
    case "$opt" in
      n) runs="$OPTARG" ;;
      o) csv="$OPTARG" ;;
      w) what="$OPTARG" ;;
      b) benches+=("$OPTARG") ;;
      h) usage 0 ;;
      *) usage ;;
    esac
  done
  shift $((OPTIND - 1))
  [ $# -ge 1 ] && [ $# -le 2 ] || usage
  command -v perf > /dev/null || die "perf is needed"
  local outs=() o
  for o in "$@"; do
    o="$(abspath "$o")"
    [ -f "$o/label" ] || die "$o was not made by refc-size.sh build"
    outs+=("$o")
  done
  [ -n "$csv" ] || csv="$(dirname "${outs[0]}")/refc-speed.csv"
  csv="$(abspath "$csv")"
  local runcsv
  runcsv="$(mktemp)"
  local work
  work="$(mktemp -d)"
  [ ${#benches[@]} -gt 0 ] || for o in "${outs[0]}"/bench/*/*/; do benches+=("$(basename "$o")"); done

  unset IDRIS2I_1_CFLAGS IDRIS2I_1_LDFLAGS IDRIS2I_1_CC IDRIS2I_1_PATH
  local r label show lib b line k
  for r in $(seq 1 "$runs"); do
    k=0
    for o in "${outs[@]}"; do
      k=$((k + 1))
      label="$(cat "$o/label")"
      # (the same OUT twice, to see the noise: the second is LABEL:2)
      show="$label"
      [ $k -eq 2 ] && [ "$label" = "$(cat "${outs[0]}/label")" ] && show="$label:2"
      if [ "$what" != bench ]; then
        for lib in prelude base; do
          rm -rf "$work/$lib"
          cp -r "$o/libsrc/$lib" "$work/$lib"
          line="$(IDRIS2I_1_PREFIX="$o/prefix" IDRIS2I_1_BUILD_JOBS=1 \
                    perf_run "$work/$lib" /dev/null "$o/stage2/exec/idris2i-1" --typecheck "$lib.ipkg")"
          echo "$show,check-$lib,$r,$line" | tee -a "$runcsv" >&2
        done
      fi
      if [ "$what" != compiler ]; then
        for b in "${benches[@]}"; do
          # refc-perf.sh runs the executable that `build` made
          rm -f "$work/perf.csv"
          "$here/refc-perf.sh" -B -d "$o/bench" -l "$label" -n 1 -o "$work/perf.csv" "$b" > /dev/null
          # label,benchmark,run,instructions,cycles,elapsed_s,maxrss_kb,status
          line="$(awk -F, 'NR > 1 { print $4 "," $5 "," $6 "," $8 }' "$work/perf.csv")"
          [ -n "$line" ] || { echo "no run of $b for $label" >&2; continue; }
          echo "$show,$b,$r,$line" | tee -a "$runcsv" >&2
        done
      fi
    done
  done
  rm -rf "$work"
  [ -s "$csv" ] || echo "label,workload,run,instructions,cycles,elapsed_s,status" > "$csv"
  cat "$runcsv" >> "$csv"
  summarise "$runcsv" "$(cat "${outs[0]}/label")"
  rm -f "$runcsv"
}

# The summary of runs: per workload and label, the mean of instructions and
# cycles with the min-max spread (in % of the mean), and the change of the
# second label from the first with the larger spread of the two.
summarise() {
  awk -F, -v first="$2" '
    $7 != 0 { bad[$1 "/" $2]++ }
    { k = $1 SUBSEP $2
      n[k]++; si[k] += $4; sc[k] += $5
      if (!(k in mini) || $4 < mini[k]) mini[k] = $4
      if (!(k in maxi) || $4 > maxi[k]) maxi[k] = $4
      if (!(k in minc) || $5 < minc[k]) minc[k] = $5
      if (!(k in maxc) || $5 > maxc[k]) maxc[k] = $5
      if (!($1 in sl)) { sl[$1] = 1; labels[++nl] = $1 }
      if (!($2 in sw)) { sw[$2] = 1; works[++nw] = $2 } }
    END {
      printf "%-16s %-14s %3s %16s %8s %16s %8s\n", "workload", "label", "n", "instructions", "spread", "cycles", "spread"
      for (w = 1; w <= nw; w++) {
        for (l = 1; l <= nl; l++) {
          k = labels[l] SUBSEP works[w]
          if (!(k in n)) continue
          mi[l] = si[k] / n[k]; mc[l] = sc[k] / n[k]
          spi[l] = 100 * (maxi[k] - mini[k]) / mi[l]; spc[l] = 100 * (maxc[k] - minc[k]) / mc[l]
          printf "%-16s %-14s %3d %16.0f %7.3f%% %16.0f %7.2f%%\n", works[w], labels[l], n[k], mi[l], spi[l], mc[l], spc[l]
        }
        if (nl == 2 && (labels[1] SUBSEP works[w]) in n && (labels[2] SUBSEP works[w]) in n) {
          di = 100 * (mi[2] - mi[1]) / mi[1]; dc = 100 * (mc[2] - mc[1]) / mc[1]
          ni = spi[1] > spi[2] ? spi[1] : spi[2]; nc = spc[1] > spc[2] ? spc[1] : spc[2]
          printf "%-16s %-14s %3s %+15.3f%% (noise %.3f%%) %+8.2f%% (noise %.2f%%)\n", "", "  change", "", di, ni, dc, nc
        }
      }
      for (b in bad) printf "WARNING: %s exited with an error in %d runs\n", b, bad[b]
    }' "$1"
}

# ---------------------------------------------------------------- padding

do_padding() {
  [ $# -eq 1 ] || usage
  local text
  text=$(size -A "$1" | awk '$1 == ".text" { print $2 }')
  # The length of an instruction is the distance to the next one.  A run of
  # NOPs ends at a function (a symbol), or inside one at a loop (the target of
  # a jump backwards) or another jump target.
  objdump -d --no-show-raw-insn -j .text "$1" | awk -v text="$text" '
    /^[0-9a-f]+ <.*>:$/ {
      addr = strtonum("0x" $1)
      if (pnop && addr > paddr) { run += addr - paddr; nop += addr - paddr }
      if (run > 0) { fn += run; nfn++ }
      run = 0; pnop = 0; next }
    /^ *[0-9a-f]+:\t/ {
      a = $1; sub(":", "", a); addr = strtonum("0x" a)
      if (pnop && addr > paddr) { run += addr - paddr; nop += addr - paddr }
      isnop = $0 ~ /:\t((data16|cs|rex[.A-Z]*) )*(nop|xchg +%ax,%ax)/
      if (!isnop && run > 0) { inside[addr] = run; run = 0 }
      if ($2 ~ /^j/ && $3 ~ /^[0-9a-f]+$/) {
        t = strtonum("0x" $3)
        if (t <= addr) back[t] = 1; else fwd[t] = 1
      }
      paddr = addr; pnop = isnop
      next }
    END {
      for (x in inside) {
        if (x in back) lp += inside[x]; else if (x in fwd) jp += inside[x]; else other += inside[x]
      }
      printf "NOP bytes %d of .text %d (%.2f%%)\n", nop, text, 100 * nop / text
      printf "  before functions %d (%.2f%%), %d functions\n", fn, 100 * fn / text, nfn
      printf "  before loops (target of a jump back) %d (%.2f%%)\n", lp, 100 * lp / text
      printf "  before other jump targets %d (%.2f%%)\n", jp, 100 * jp / text
      printf "  elsewhere (no jump to it seen) %d (%.2f%%)\n", other, 100 * other / text
    }'
}

# ---------------------------------------------------------------- main

[ $# -ge 1 ] || usage
mode="$1"; shift
case "$mode" in
  build) do_build "$@" ;;
  sizes) do_sizes "$@" ;;
  measure) do_measure "$@" ;;
  padding) do_padding "$@" ;;
  -h|help) usage 0 ;;
  *) usage ;;
esac
