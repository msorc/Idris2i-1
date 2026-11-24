#!/bin/sh

set -e # exit on any error

if [ -z "$SCHEME" ] || [ -z "$IDRIS2I_1_VERSION" ]; then
    echo "Required SCHEME or IDRIS2I_1_VERSION env is not set."
    if [ -z "$SCHEME" ]; then
        echo "Invoke with SCHEME=[name of chez scheme executable]"
    fi
    exit 1
fi
echo "Bootstrapping SCHEME=$SCHEME IDRIS2I_1_VERSION=$IDRIS2I_1_VERSION"

# Compile the bootstrap scheme
# TODO: Move boot-build to Makefile in bootstrap/Makefile
cd bootstrap-build
echo "Building idris2i-1-boot from idris2i-1-boot.ss"
"${SCHEME}" --script ../bootstrap/compile.ss

# Put the result in the usual place where the target goes
mkdir -p ../build/exec
mkdir -p ../build/exec/idris2i-1_app

# we "install" bootstrap/idris2i-1-boot.sh as build/exec/idris2i-1
# but with the SCHEME var that we already know at this time
# baked into it.
echo '#!/bin/sh' >../build/exec/idris2i-1
echo "SCHEME=\"${SCHEME}\"" >>../build/exec/idris2i-1
cat ../bootstrap/idris2i-1-boot.sh >>../build/exec/idris2i-1
chmod +x ../build/exec/idris2i-1
if [ "$OS" = windows ] || [ "$OS" = Windows_NT ]; then
    install ../bootstrap/idris2i-1.cmd ../build/exec/idris2i-1.cmd
fi
install idris2i-1_app/* ../build/exec/idris2i-1_app
echo 'bootstrap stage 1 complete'
