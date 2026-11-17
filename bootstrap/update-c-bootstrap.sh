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
# idris2_caf_IdrisPaths_yprefix, or IdrisPaths_yprefix_constant in older
# compilers, which IdrisPaths_yprefix calls once.)  Only the returns inside
# these functions are looked at, up to the brace that closes each.
CONST="$(awk '/^(static )?Idris2_Value \*(idris2_caf_)?IdrisPaths_yprefix(_constant)?\(void\)$/ { found = 1; next }
              found && /^}/ { found = 0; next }
              found && /return/ { if (match($0, /idris2_constant_String_[0-9A-Za-z_]+/)) {
                                    print substr($0, RSTART, RLENGTH); exit } }' "$SRC")"
if [ -z "$CONST" ]; then
    echo "Could not find the definition of IdrisPaths.yprefix in $SRC"
    exit 1
fi

# The constant of an ASCII string (IDRIS2_ASCII_STRING_CONSTANT) records that
# its characters are its bytes: the prefix that `make bootstrap-c` puts there
# may not be ASCII, so it becomes a plain string constant, whose characters
# are counted when needed.
sed "s|^IDRIS2_\(ASCII_\)\{0,1\}STRING_CONSTANT($CONST, \".*\");$|IDRIS2_STRING_CONSTANT($CONST, \"__PREFIX__\");|" "$SRC" \
    | xz -9 -T0 > "$OUT"

if ! xz -dc "$OUT" | grep -q "^IDRIS2_STRING_CONSTANT($CONST, \"__PREFIX__\");$"; then
    echo "Could not replace the prefix in $SRC"
    exit 1
fi
echo "Wrote $OUT"
