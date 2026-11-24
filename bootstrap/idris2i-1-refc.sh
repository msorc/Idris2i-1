#!/bin/sh

# Launcher for an Idris2i-1 compiler built with the RefC backend.  The compiler
# lives in idris2i-1_app/idris2i-1 next to this script.

if [ "$(uname)" = Darwin ]; then
    DIR="$(zsh -c 'printf %s "$0:A:h"' "$0")"
else
    DIR="$(dirname "$(readlink -f -- "$0")")"
fi

# The compiler recurses deeply.  A program compiled with RefC runs its main
# expression on a large stack of its own (IDRIS2I_1_MAIN_STACK_SIZE), which
# ulimit -s does not limit; but where that stack cannot be allocated (or the
# platform has no green threads) it runs on the stack of the process, so lift
# the stack limit as far as it goes, as a fallback.
ulimit -s unlimited 2>/dev/null || ulimit -s "$(ulimit -H -s)" 2>/dev/null || true

export LD_LIBRARY_PATH="$DIR/idris2i-1_app:$LD_LIBRARY_PATH"
export DYLD_LIBRARY_PATH="$DIR/idris2i-1_app:$DYLD_LIBRARY_PATH"

exec "$DIR/idris2i-1_app/idris2i-1" "$@"
