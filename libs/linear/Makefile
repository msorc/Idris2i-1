all: build
.PHONY: all

build:
	${IDRIS2I_1} --build linear.ipkg
.PHONY: build

install:
	${IDRIS2I_1} --install linear.ipkg
.PHONY: install

install-with-src:
	${IDRIS2I_1} --install-with-src linear.ipkg
.PHONY: install-with-src

docs:
	${IDRIS2I_1} --mkdoc linear.ipkg
.PHONY: docs

clean:
	$(RM) -r build
.PHONY: clean
