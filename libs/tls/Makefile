all: build
.PHONY: all

# The C part is also copied into the `lib` directory next to the TTC files
# of the build: the libraries of the tree are used from there before they
# are installed (by IDRIS2I_1_PATH, and by the test environment, which links
# build/ttc as the installed package).
build:
	${IDRIS2I_1} --build tls.ipkg
	mkdir -p build/ttc/lib
	cp c/libidris2i_1_tls.a c/idris_tls.h build/ttc/lib/
	for f in c/libidris2i_1_tls.so c/libidris2i_1_tls.dylib; do \
	  if [ -f "$$f" ]; then cp "$$f" build/ttc/lib/; fi; \
	done
.PHONY: build

install:
	${IDRIS2I_1} --install tls.ipkg
.PHONY: install

install-with-src:
	${IDRIS2I_1} --install-with-src tls.ipkg
.PHONY: install-with-src

docs:
	${IDRIS2I_1} --mkdoc tls.ipkg
.PHONY: docs

clean:
	$(RM) -r build
	${MAKE} -C c clean
.PHONY: clean
