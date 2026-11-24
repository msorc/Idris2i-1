all: build
.PHONY: all

build:
	${IDRIS2I_1} --build network.ipkg
.PHONY: build

install:
	${IDRIS2I_1} --install network.ipkg
.PHONY: install

install-with-src:
	${IDRIS2I_1} --install-with-src network.ipkg
.PHONY: install-with-src

docs:
	${IDRIS2I_1} --mkdoc network.ipkg
.PHONY: docs

clean:
	$(RM) -r build
.PHONY: clean

