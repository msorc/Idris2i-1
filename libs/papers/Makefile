all: build
.PHONY: all

build:
	${IDRIS2I_1} --build papers.ipkg
.PHONY: build

install:
	${IDRIS2I_1} --install papers.ipkg
.PHONY: install

install-with-src:
	${IDRIS2I_1} --install-with-src papers.ipkg
.PHONY: install-with-src

docs:
	${IDRIS2I_1} --mkdoc papers.ipkg
.PHONY: docs

clean:
	$(RM) -r build
.PHONY: clean
