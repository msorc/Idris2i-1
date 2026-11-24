all: build
.PHONY: all

build:
	${IDRIS2I_1} --build http.ipkg
.PHONY: build

install:
	${IDRIS2I_1} --install http.ipkg
.PHONY: install

install-with-src:
	${IDRIS2I_1} --install-with-src http.ipkg
.PHONY: install-with-src

docs:
	${IDRIS2I_1} --mkdoc http.ipkg
.PHONY: docs

clean:
	$(RM) -r build
.PHONY: clean

