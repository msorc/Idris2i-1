#!/bin/sh

set -e # exit on any error

if [ -z "$IDRIS2I_1_VERSION" ]; then
    echo "Required IDRIS2I_1_VERSION env is not set."
    exit 1
fi
echo "Bootstrapping IDRIS2I_1_VERSION=$IDRIS2I_1_VERSION"

# Compile the bootstrap scheme
cd bootstrap-build
echo "Building idris2i-1-boot from idris2i-1-boot.rkt"
raco exe idris2i-1_app/idris2i-1-boot.rkt

# Put the result in the usual place where the target goes
mkdir -p ../build/exec
mkdir -p ../build/exec/idris2i-1_app
install ../bootstrap/idris2i-1-rktboot.sh ../build/exec/idris2i-1
if [ "$OS" = windows ] || [ "$OS" = Windows_NT ]; then
    install ../bootstrap/idris2i-1.cmd ../build/exec/idris2i-1.cmd
fi
install idris2i-1_app/* ../build/exec/idris2i-1_app

echo 'bootstrap stage 1 complete'
