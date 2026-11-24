all: build
.PHONY: all

build:
	${IDRIS2I_1} --build test.ipkg
.PHONY: build

install:
	${IDRIS2I_1} --install test.ipkg
.PHONY: install

install-with-src:
	${IDRIS2I_1} --install-with-src test.ipkg
.PHONY: install-with-src

docs:
	${IDRIS2I_1} --mkdoc test.ipkg
.PHONY: docs

clean:
	$(RM) -r build
.PHONY: clean
