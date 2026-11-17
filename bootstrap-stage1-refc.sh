#!/bin/sh

set -e # exit on any error

if [ -z "$IDRIS2_VERSION" ]; then
    echo "Required IDRIS2_VERSION env is not set."
    exit 1
fi

CC="${CC:-cc}"
SUPPORT_C="${IDRIS2_SUPPORT_DIR:-$PWD/support/c}"
SUPPORT_REFC="$PWD/support/refc"

# The generated code is split in chunks (see generateCSourceFile in
# src/Compiler/RefC/RefC.idr): it is compiled in BOOT_PARTS parts, by
# BOOT_JOBS C compilers running at once.  Each C compiler reads the whole file
# but compiles only its part, and the memory that it needs is mostly that of
# its part: with -O1 and GCC, about 0.9 GB for a part of 16 (and 2.1 GB for a
# part of 6, the whole compiler taking about 13 GB).  So the number of parts
# does not depend on the machine: 16 by default (or BOOT_JOBS when it is
# more), and BOOT_JOBS is the number of processors, up to 16, and on Linux up
# to one per 1.5 GB of available memory.  A file without chunks is compiled
# whole.
if [ -z "$BOOT_JOBS" ]; then
    BOOT_JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
    [ "$BOOT_JOBS" -gt 16 ] && BOOT_JOBS=16
    if [ -r /proc/meminfo ]; then
        mem_jobs=$(awk '/^MemAvailable:/ { print int($2 / (1.5 * 1024 * 1024)) }' /proc/meminfo)
        if [ -n "$mem_jobs" ]; then
            [ "$mem_jobs" -lt 1 ] && mem_jobs=1
            [ "$BOOT_JOBS" -gt "$mem_jobs" ] && BOOT_JOBS=$mem_jobs
        fi
    fi
fi
if [ -z "$BOOT_PARTS" ]; then
    BOOT_PARTS=16
    [ "$BOOT_JOBS" -gt "$BOOT_PARTS" ] && BOOT_PARTS=$BOOT_JOBS
fi
if ! grep -q '^#if !defined(IDRIS2_PARTS)' bootstrap-build/idris2_app/idris2-boot.c; then
    BOOT_JOBS=1
    BOOT_PARTS=1
fi
[ "$BOOT_JOBS" -gt "$BOOT_PARTS" ] && BOOT_JOBS=$BOOT_PARTS

# The stage 1 compiler only builds the four bootstrap libraries and the stage 2
# compiler, which is the one that is installed (see bootstrap-stage2.sh).  So
# its C is compiled quickly: -O1, and no link time optimisation, which would
# buy a few percent of speed for about twice the build time.  Set BOOT_CFLAGS
# (possibly empty) to change that, for instance to "-O2 -flto=auto".  -Werror
# is not used, warnings in generated code depend on the C compiler.
BOOT_CFLAGS="${BOOT_CFLAGS-"-O1"}"

echo "Bootstrapping CC=$CC IDRIS2_VERSION=$IDRIS2_VERSION"

cd bootstrap-build
echo "Building idris2-boot from idris2-boot.c in $BOOT_PARTS parts, $BOOT_JOBS at a time ($BOOT_CFLAGS)"
objs=
k=0
while [ "$k" -lt "$BOOT_PARTS" ]; do
    objs="$objs idris2_app/idris2-boot.$k.o"
    k=$((k + 1))
done
# Workers that take the parts one by one: a part is claimed by making a
# directory for it.  After a failure, the workers do not start new parts.
claims="idris2_app/idris2-boot.claims.$$"
rm -rf "$claims"
mkdir "$claims"
worker() {
    k=0
    while [ "$k" -lt "$BOOT_PARTS" ]; do
        if [ ! -e "$claims/failed" ] && mkdir "$claims/$k" 2>/dev/null; then
            # shellcheck disable=SC2086 # the flags are lists of words
            "$CC" $BOOT_CFLAGS $CPPFLAGS -DIDRIS2_PARTS="$BOOT_PARTS" -DIDRIS2_PART="$k" \
                -c idris2_app/idris2-boot.c -o "idris2_app/idris2-boot.$k.o" \
                -I"$SUPPORT_REFC" -I"$SUPPORT_C" || { : >"$claims/failed"; return 1; }
        fi
        k=$((k + 1))
    done
}
pids=
j=0
while [ "$j" -lt "$BOOT_JOBS" ]; do
    worker &
    pids="$pids $!"
    j=$((j + 1))
done
status=0
for pid in $pids; do
    wait "$pid" || status=1
done
rm -rf "$claims"
if [ "$status" -ne 0 ]; then
    echo "Compiling idris2-boot.c failed"
    exit 1
fi
# shellcheck disable=SC2086
"$CC" $BOOT_CFLAGS $objs -o idris2_app/idris2 \
    "$SUPPORT_C/libidris2_support.a" "$SUPPORT_REFC/libidris2_refc.a" \
    $LDFLAGS -lgmp -lm -pthread $LDLIBS

# Put the result in the usual place where the target goes
mkdir -p ../build/exec/idris2_app
install idris2_app/idris2 ../build/exec/idris2_app/idris2
install ../bootstrap/idris2-refc.sh ../build/exec/idris2
echo 'bootstrap stage 1 complete'
