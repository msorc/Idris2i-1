# Copy the C part of the library into the `lib` directory of the installed
# package (run by `idris2 --install`, in the directory of tls.ipkg).
set -e
mkdir -p "$IDRIS2_PACKAGE_INSTALL_DIR/lib"
cp c/libidris2_tls.a c/idris_tls.h "$IDRIS2_PACKAGE_INSTALL_DIR/lib/"
for f in c/libidris2_tls.so c/libidris2_tls.dylib; do
  if [ -f "$f" ]; then cp "$f" "$IDRIS2_PACKAGE_INSTALL_DIR/lib/"; fi
done
