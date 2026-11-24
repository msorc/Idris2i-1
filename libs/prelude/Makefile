all: build
.PHONY: all

build:
	${IDRIS2I_1} --build prelude.ipkg
.PHONY: build

install:
	${IDRIS2I_1} --install prelude.ipkg
.PHONY: install

install-with-src:
	${IDRIS2I_1} --install-with-src prelude.ipkg
.PHONY: install-with-src

docs:
	${IDRIS2I_1} --mkdoc prelude.ipkg
.PHONY: docs

clean:
	$(RM) -r build
.PHONY: clean
