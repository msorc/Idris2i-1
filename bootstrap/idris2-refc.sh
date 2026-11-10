#!/bin/sh

# Launcher for an Idris 2 compiler built with the RefC backend.  The compiler
# lives in idris2_app/idris2 next to this script.

if [ "$(uname)" = Darwin ]; then
    DIR="$(zsh -c 'printf %s "$0:A:h"' "$0")"
else
    DIR="$(dirname "$(readlink -f -- "$0")")"
fi

# The compiler recurses deeply and the RefC backend runs the main program on
# the stack of the process, so lift the stack limit as far as it goes.
ulimit -s unlimited 2>/dev/null || ulimit -s "$(ulimit -H -s)" 2>/dev/null || true

export LD_LIBRARY_PATH="$DIR/idris2_app:$LD_LIBRARY_PATH"
export DYLD_LIBRARY_PATH="$DIR/idris2_app:$DYLD_LIBRARY_PATH"

exec "$DIR/idris2_app/idris2" "$@"
