all: build
.PHONY: all

build:
	${IDRIS2I_1} --build base.ipkg
.PHONY: build

install:
	${IDRIS2I_1} --install base.ipkg
.PHONY: install

install-with-src:
	${IDRIS2I_1} --install-with-src base.ipkg
.PHONY: install-with-src

docs:
	${IDRIS2I_1} --mkdoc base.ipkg
.PHONY: docs

clean:
	$(RM) -r build
.PHONY: clean
