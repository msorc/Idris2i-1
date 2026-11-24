#!/bin/sh

IDRIS2I_1_DIR=Idris2i-1-"$1"

set -e

if [ $# -eq 0 ]; then
    echo "No version number supplied"
    exit 1
fi

git clone https://github.com/idris-lang/Idris2.git
mv Idris2i-1 "$IDRIS2I_1_DIR"
cd "$IDRIS2I_1_DIR"

# Go to the tag for the release we're making
git checkout tags/v"$1"

# Remove the directories and files we don't want in the release
rm -rf .git
rm -rf .github
rm .git*
rm -rf Release
rm -rf benchmark
find . -type f -name '.gitignore' -exec rm -f {} \;

cd ..

tar zcf idris2i-1-"$1".tgz "$IDRIS2I_1_DIR"

echo "idris2i-1-$1.tgz created."
