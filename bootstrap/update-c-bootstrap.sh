#!/bin/sh

# Turn the C code that the RefC backend generated for the compiler into the
# bootstrap source bootstrap/idris2_app/idris2.c.xz:  the installation prefix
# baked into it (IdrisPaths.yprefix) is replaced by __PREFIX__, which
# `make bootstrap-c` substitutes back.
#
# Usage: bootstrap/update-c-bootstrap.sh build/exec/idris2.c

set -e

SRC="$1"
OUT="$(dirname "$0")/idris2_app/idris2.c.xz"

if [ ! -f "$SRC" ]; then
    echo "Usage: $0 <generated idris2.c>"
    exit 1
fi

# The body of IdrisPaths_yprefix returns a string constant; find its name.
# (The body of a definition without arguments is in a function of its own,
# IdrisPaths_yprefix_constant, which IdrisPaths_yprefix calls once.)
CONST="$(awk '/^(static )?Idris2_Value \*IdrisPaths_yprefix(_constant)?\(void\)$/ { found = 1; next }
              found && /return/ { if (match($0, /idris2_constant_String_[0-9]+/)) {
                                    print substr($0, RSTART, RLENGTH); exit } }' "$SRC")"
if [ -z "$CONST" ]; then
    echo "Could not find the definition of IdrisPaths.yprefix in $SRC"
    exit 1
fi

sed "s|^\(static Idris2_String const $CONST = { IDRIS2_STOCKVAL(STRING_TAG), \)\".*\"\( };\)$|\1\"__PREFIX__\"\2|" "$SRC" \
    | xz -9 -T0 > "$OUT"

if ! xz -dc "$OUT" | grep -q "^static Idris2_String const $CONST = { IDRIS2_STOCKVAL(STRING_TAG), \"__PREFIX__\" };$"; then
    echo "Could not replace the prefix in $SRC"
    exit 1
fi
echo "Wrote $OUT"
