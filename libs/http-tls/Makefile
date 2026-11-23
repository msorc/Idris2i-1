all: build
.PHONY: all

build:
	${IDRIS2} --build http-tls.ipkg
.PHONY: build

install:
	${IDRIS2} --install http-tls.ipkg
.PHONY: install

install-with-src:
	${IDRIS2} --install-with-src http-tls.ipkg
.PHONY: install-with-src

docs:
	${IDRIS2} --mkdoc http-tls.ipkg
.PHONY: docs

clean:
	$(RM) -r build
.PHONY: clean

