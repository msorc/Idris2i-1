# Run by `idris2i-1 --install` once the package is installed, in the directory
# of the package file: IDRIS2I_1_PACKAGE_INSTALL_DIR is where it was installed.
set -e
mkdir -p "$IDRIS2I_1_PACKAGE_INSTALL_DIR/lib"
cp libanswer.a answer.h "$IDRIS2I_1_PACKAGE_INSTALL_DIR/lib/"
