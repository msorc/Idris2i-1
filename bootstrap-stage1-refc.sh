#!/bin/sh

set -e # exit on any error

if [ -z "$IDRIS2_VERSION" ]; then
    echo "Required IDRIS2_VERSION env is not set."
    exit 1
fi

CC="${CC:-cc}"
# The generated code is big: -O1 gives most of the speed of -O2 for a fraction
# of the compile time.  -Werror is not used, warnings in generated code depend
# on the C compiler.
BOOT_CFLAGS="${BOOT_CFLAGS:--O1}"

SUPPORT_C="${IDRIS2_SUPPORT_DIR:-$PWD/support/c}"
SUPPORT_REFC="$PWD/support/refc"

echo "Bootstrapping CC=$CC IDRIS2_VERSION=$IDRIS2_VERSION"

cd bootstrap-build
echo "Building idris2-boot from idris2-boot.c"
# shellcheck disable=SC2086 # the flags are lists of words
"$CC" $BOOT_CFLAGS $CPPFLAGS -c idris2_app/idris2-boot.c \
    -o idris2_app/idris2-boot.o -I"$SUPPORT_REFC" -I"$SUPPORT_C"
# shellcheck disable=SC2086
"$CC" $BOOT_CFLAGS idris2_app/idris2-boot.o -o idris2_app/idris2 \
    "$SUPPORT_C/libidris2_support.a" "$SUPPORT_REFC/libidris2_refc.a" \
    $LDFLAGS -lgmp -lm $LDLIBS

# Put the result in the usual place where the target goes
mkdir -p ../build/exec/idris2_app
install idris2_app/idris2 ../build/exec/idris2_app/idris2
install ../bootstrap/idris2-refc.sh ../build/exec/idris2
echo 'bootstrap stage 1 complete'
