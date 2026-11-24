#!/bin/sh

set -e # exit on any error

if [ "$OS" = windows ] || [ "$OS" = Windows_NT ]; then
    BOOTSTRAP_PREFIX=$(cygpath -m "$PWD")/bootstrap-build
else
    BOOTSTRAP_PREFIX=$PWD/bootstrap-build
fi

IDRIS2I_1_CG="${IDRIS2I_1_CG-"refc"}"

echo "bootstrapping in: $BOOTSTRAP_PREFIX"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-"${BOOTSTRAP_PREFIX}/lib"}"
export DYLD_LIBRARY_PATH="${DYLD_LIBRARY_PATH:-"${BOOTSTRAP_PREFIX}/lib"}"
export IDRIS2I_1_DATA="${IDRIS2I_1_DATA:-"${BOOTSTRAP_PREFIX}/support"}"

$MAKE bootstrap-libs IDRIS2I_1_CG="$IDRIS2I_1_CG" \
    PREFIX="$BOOTSTRAP_PREFIX" SCHEME="$SCHEME"
$MAKE bootstrap-install IDRIS2I_1_CG="$IDRIS2I_1_CG" \
    PREFIX="$BOOTSTRAP_PREFIX" SCHEME="$SCHEME"

# Now rebuild everything properly
$MAKE clean-libs IDRIS2I_1_BOOT="$BOOTSTRAP_PREFIX/bin/idris2i-1"
# This compiler is the one that is installed: build its C with link time
# optimisation (RefC), unless LTO is set (to 0 for a quick build).
$MAKE all IDRIS2I_1_BOOT="$BOOTSTRAP_PREFIX/bin/idris2i-1" IDRIS2I_1_CG="$IDRIS2I_1_CG" \
    SCHEME="$SCHEME" LTO="${LTO:-1}"
echo 'bootstrap stage 2 complete'
