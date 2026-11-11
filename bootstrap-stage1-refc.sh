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
# src/Compiler/RefC/RefC.idr): compile it in BOOT_JOBS parts in parallel.
# A file without chunks is compiled whole.
BOOT_JOBS="${BOOT_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"
if ! grep -q '^#if !defined(IDRIS2_PARTS)' bootstrap-build/idris2_app/idris2-boot.c; then
    BOOT_JOBS=1
fi

# Link time optimisation gives back the inlining across parts (about 5% of
# the speed of the compiler) when the C compiler supports it.  -Werror is not
# used, warnings in generated code depend on the C compiler.
if [ -z "${BOOT_CFLAGS+set}" ]; then
    BOOT_CFLAGS=-O2
    if [ "$BOOT_JOBS" -gt 1 ] && sh "$PWD/bootstrap/cc-has-lto.sh" "$CC"; then
        BOOT_CFLAGS="-O2 -flto=auto"
    fi
fi

echo "Bootstrapping CC=$CC IDRIS2_VERSION=$IDRIS2_VERSION"

cd bootstrap-build
echo "Building idris2-boot from idris2-boot.c in $BOOT_JOBS parts ($BOOT_CFLAGS)"
pids=
objs=
k=0
while [ "$k" -lt "$BOOT_JOBS" ]; do
    # shellcheck disable=SC2086 # the flags are lists of words
    "$CC" $BOOT_CFLAGS $CPPFLAGS -DIDRIS2_PARTS="$BOOT_JOBS" -DIDRIS2_PART="$k" \
        -c idris2_app/idris2-boot.c -o "idris2_app/idris2-boot.$k.o" \
        -I"$SUPPORT_REFC" -I"$SUPPORT_C" &
    pids="$pids $!"
    objs="$objs idris2_app/idris2-boot.$k.o"
    k=$((k + 1))
done
status=0
for pid in $pids; do
    wait "$pid" || status=1
done
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
