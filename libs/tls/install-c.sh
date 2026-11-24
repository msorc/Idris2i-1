# Copy the C part of the library into the `lib` directory of the installed
# package (run by `idris2i-1 --install`, in the directory of tls.ipkg).
set -e
mkdir -p "$IDRIS2I_1_PACKAGE_INSTALL_DIR/lib"
cp c/libidris2i_1_tls.a c/idris_tls.h "$IDRIS2I_1_PACKAGE_INSTALL_DIR/lib/"
for f in c/libidris2i_1_tls.so c/libidris2i_1_tls.dylib; do
  if [ -f "$f" ]; then cp "$f" "$IDRIS2I_1_PACKAGE_INSTALL_DIR/lib/"; fi
done
