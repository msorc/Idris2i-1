all: build
.PHONY: all

build:
	${IDRIS2} --build http.ipkg
.PHONY: build

install:
	${IDRIS2} --install http.ipkg
.PHONY: install

install-with-src:
	${IDRIS2} --install-with-src http.ipkg
.PHONY: install-with-src

docs:
	${IDRIS2} --mkdoc http.ipkg
.PHONY: docs

clean:
	$(RM) -r build
.PHONY: clean

