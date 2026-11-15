include config.mk

# Idris 2 executable used to bootstrap
export IDRIS2_BOOT ?= idris2

# Idris 2 executable we're building
NAME = idris2
TARGETDIR = ${CURDIR}/build/exec
TARGET = ${TARGETDIR}/${NAME}

# Default code generator. This is passed to the libraries for incremental
# builds, but overridable via environment variables or arguments to make
IDRIS2_CG ?= refc

# How many processes build the modules of the compiler and of the libraries in
# parallel (IDRIS2_BUILD_JOBS of the compiler that builds them, which older
# compilers ignore): the number of processors, up to 16.  1 builds them one
# after the other.
IDRIS2_JOBS ?= $(shell n=$$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1); [ "$$n" -gt 16 ] && n=16; echo $$n)
JOBS_ENV = IDRIS2_BUILD_JOBS=${IDRIS2_JOBS}

MAJOR=0
MINOR=8
PATCH=0

GIT_SHA1=
ifeq ($(shell git status >/dev/null 2>&1; echo $$?), 0)
	# inside a git repo
	ifneq ($(shell git describe --exact-match --tags >/dev/null 2>&1; echo $$?), 0)
		# not tagged as a released version, so add sha1 of this build in between releases
		GIT_SHA1 := $(shell git rev-parse --short=9 HEAD)
	endif
endif
VERSION_TAG ?= $(GIT_SHA1)

export IDRIS2_VERSION := ${MAJOR}.${MINOR}.${PATCH}
export NAME_VERSION := ${NAME}-${IDRIS2_VERSION}
IDRIS2_SUPPORT := libidris2_support${SHLIB_SUFFIX}
IDRIS2_APP_IPKG := idris2.ipkg
IDRIS2_LIB_IPKG := idris2api.ipkg

ifeq ($(OS), windows)
	# This produces D:/../.. style paths
	IDRIS2_PREFIX ?= $(shell cygpath -m ${PREFIX})
	IDRIS2_CURDIR := $(shell cygpath -m ${CURDIR})
	SEP := ;
	LINK_CMD = cp -rf
else
	IDRIS2_PREFIX ?= ${PREFIX}
	IDRIS2_CURDIR := ${CURDIR}
	SEP := :
	LINK_CMD = ln -sf
endif

IDRIS2_SUPPORT_DIR ?= ${IDRIS2_CURDIR}/support/c

TEST_PREFIX ?= ${IDRIS2_CURDIR}/build/env

TEST_IDRIS2_SUPPORT_DIR ?= ${TEST_PREFIX}/${NAME_VERSION}

# Library and data paths for bootstrap-test
IDRIS2_BOOT_PREFIX := ${IDRIS2_CURDIR}/bootstrap-build

# These are the library path in the build dir to be used during build
IDRIS2_LIBRARIES = prelude base linear network contrib test

IDRIS2_BOOT_PATH =
$(foreach library,$(IDRIS2_LIBRARIES),$(eval IDRIS2_BOOT_PATH := $(IDRIS2_BOOT_PATH)$(IDRIS2_CURDIR)/libs/$(library)/build/ttc$(SEP)))
export IDRIS2_BOOT_PATH := "$(IDRIS2_BOOT_PATH)"

export SCHEME

.PHONY: all idris2-exec libdocs testenv testenv-clean support clean-support clean FORCE

all:
	${MAKE} ${TARGET}
	${MAKE} libs

idris2-exec: ${TARGET}

${TARGET}: support src/IdrisPaths.idr
ifeq ($(IDRIS2_CG), refc)
	# Optimise the generated C unless told otherwise (older compilers, like the
	# one of bootstrap-c, do not do it by default).  The compiler is compiled
	# in parts in parallel: link time optimisation, when the C compiler has it,
	# gives back the inlining across parts.
	LTO=$$(sh bootstrap/cc-has-lto.sh "$${IDRIS2_CC:-$${CC:-cc}}" && echo " -flto=auto"); \
	IDRIS2_CFLAGS="$${IDRIS2_CFLAGS:-$${CFLAGS:--O2$$LTO}}" ${JOBS_ENV} ${IDRIS2_BOOT} --build ${IDRIS2_APP_IPKG}
else
	${JOBS_ENV} ${IDRIS2_BOOT} --build ${IDRIS2_APP_IPKG}
endif
ifeq ($(IDRIS2_CG), refc)
	# RefC builds a single binary: give it the layout of the Scheme backends,
	# a launcher next to an idris2_app directory.
	mkdir -p ${TARGETDIR}/${NAME}_app
	mv -f ${TARGET} ${TARGETDIR}/${NAME}_app/${NAME}
	install bootstrap/idris2-refc.sh ${TARGET}
endif
	cp ${IDRIS2_SUPPORT_DIR}/${IDRIS2_SUPPORT} ${TARGETDIR}/${NAME}_app/${IDRIS2_SUPPORT}

# We use FORCE to always rebuild IdrisPath so that the git SHA1 info is always up to date
src/IdrisPaths.idr: FORCE
	echo "-- @""generated" > src/IdrisPaths.idr
	echo 'module IdrisPaths' >> src/IdrisPaths.idr
	echo 'export idrisVersion : ((Nat,Nat,Nat), String); idrisVersion = ((${MAJOR},${MINOR},${PATCH}), "${VERSION_TAG}")' >> src/IdrisPaths.idr
	echo 'export yprefix : String; yprefix="${IDRIS2_PREFIX}"' >> src/IdrisPaths.idr

FORCE:

prelude:
	${JOBS_ENV} ${MAKE} -C libs/prelude IDRIS2=${TARGET} IDRIS2_INC_CGS=${IDRIS2_CG} IDRIS2_PATH=${IDRIS2_BOOT_PATH}

base: prelude
	${JOBS_ENV} ${MAKE} -C libs/base IDRIS2=${TARGET} IDRIS2_INC_CGS=${IDRIS2_CG} IDRIS2_PATH=${IDRIS2_BOOT_PATH}

network: prelude linear
	${JOBS_ENV} ${MAKE} -C libs/network IDRIS2=${TARGET} IDRIS2_INC_CGS=${IDRIS2_CG} IDRIS2_PATH=${IDRIS2_BOOT_PATH}

contrib: base
	${JOBS_ENV} ${MAKE} -C libs/contrib IDRIS2=${TARGET} IDRIS2_INC_CGS=${IDRIS2_CG} IDRIS2_PATH=${IDRIS2_BOOT_PATH}

test-lib: contrib
	${JOBS_ENV} ${MAKE} -C libs/test IDRIS2=${TARGET} IDRIS2_INC_CGS=${IDRIS2_CG} IDRIS2_PATH=${IDRIS2_BOOT_PATH}

linear: prelude base
	${JOBS_ENV} ${MAKE} -C libs/linear IDRIS2=${TARGET} IDRIS2_INC_CGS=${IDRIS2_CG} IDRIS2_PATH=${IDRIS2_BOOT_PATH}

papers: contrib linear
	${JOBS_ENV} ${MAKE} -C libs/papers IDRIS2=${TARGET} IDRIS2_INC_CGS=${IDRIS2_CG} IDRIS2_PATH=${IDRIS2_BOOT_PATH}

bootstrap-libs : prelude base linear network
libs : prelude base contrib network test-lib linear papers

libdocs:
	${JOBS_ENV} ${MAKE} -C libs/prelude docs IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH}
	${JOBS_ENV} ${MAKE} -C libs/base docs IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH}
	${JOBS_ENV} ${MAKE} -C libs/contrib docs IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH}
	${JOBS_ENV} ${MAKE} -C libs/network docs IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH}
	${JOBS_ENV} ${MAKE} -C libs/test docs IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH}
	${JOBS_ENV} ${MAKE} -C libs/linear docs IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH}

${TEST_PREFIX}/${NAME_VERSION} :
	${LINK_CMD} ${IDRIS2_CURDIR}/libs/prelude/build/ttc ${TEST_PREFIX}/${NAME_VERSION}/prelude-${IDRIS2_VERSION}
	${LINK_CMD} ${IDRIS2_CURDIR}/libs/base/build/ttc    ${TEST_PREFIX}/${NAME_VERSION}/base-${IDRIS2_VERSION}
	${LINK_CMD} ${IDRIS2_CURDIR}/libs/linear/build/ttc  ${TEST_PREFIX}/${NAME_VERSION}/linear-${IDRIS2_VERSION}
	${LINK_CMD} ${IDRIS2_CURDIR}/libs/network/build/ttc ${TEST_PREFIX}/${NAME_VERSION}/network-${IDRIS2_VERSION}
	${LINK_CMD} ${IDRIS2_CURDIR}/libs/contrib/build/ttc ${TEST_PREFIX}/${NAME_VERSION}/contrib-${IDRIS2_VERSION}
	${LINK_CMD} ${IDRIS2_CURDIR}/libs/test/build/ttc    ${TEST_PREFIX}/${NAME_VERSION}/test-${IDRIS2_VERSION}

.PHONY: ${TEST_PREFIX}/${NAME_VERSION}

# The support libraries that the tests use, installed under TEST_PREFIX.  This
# always goes through support (which rebuilds what changed) and reinstalls: a
# check on the installed files would not see a change of the sources.
test-support:
	${MAKE} install-support PREFIX=${TEST_PREFIX}

testenv: test-support
	mkdir -p ${TEST_PREFIX}/${NAME_VERSION}
	@${MAKE} ${TEST_PREFIX}/${NAME_VERSION}
	@${MAKE} -C tests testbin IDRIS2=${TARGET} IDRIS2_PREFIX=${TEST_PREFIX}

testenv-clean:
	$(RM) -r ${TEST_PREFIX}/${NAME_VERSION}

ci-ubuntu-test: test
ci-macos-test: test
ci-windows-test:
	@${MAKE} test except="idris2/repl005"

test: testenv
	@echo
	@echo "NOTE: \`${MAKE} test\` does not rebuild Idris or the libraries packaged with it; to do that run \`${MAKE}\`"
	@if [ ! -x "${TARGET}" ]; then echo "ERROR: Missing IDRIS2 executable. Cannot run tests!\n"; exit 1; fi
	@echo
	@${MAKE} -C tests only=$(only) except=$(except) IDRIS2=${TARGET} IDRIS2_PREFIX=${TEST_PREFIX} CPPFLAGS="${CPPFLAGS}" LDFLAGS="${LDFLAGS}"


retest: testenv
	@echo
	@echo "NOTE: \`${MAKE} retest\` does not rebuild Idris or the libraries packaged with it; to do that run \`${MAKE}\`"
	@if [ ! -x "${TARGET}" ]; then echo "ERROR: Missing IDRIS2 executable. Cannot run tests!\n"; exit 1; fi
	@echo
	@${MAKE} -C tests retest only=$(only) IDRIS2=${TARGET} IDRIS2_PREFIX=${TEST_PREFIX}

test-installed:
	@${MAKE} -C tests testbin      IDRIS2=$(IDRIS2_PREFIX)/bin/idris2 IDRIS2_PREFIX=${IDRIS2_PREFIX}
	@${MAKE} -C tests only=$(only) IDRIS2=$(IDRIS2_PREFIX)/bin/idris2 IDRIS2_PREFIX=${IDRIS2_PREFIX}

# Build the support libraries (in support/, where the Makefiles rebuild what
# changed since the last time, so this does not use the file as a target).
# When IDRIS2_SUPPORT_DIR points elsewhere, to support libraries that were
# built beforehand (see bootstrap), they are only checked for.
ifeq (${IDRIS2_SUPPORT_DIR},${IDRIS2_CURDIR}/support/c)
support:
	@${MAKE} -C support
else
support:
	@if [ ! -f "${IDRIS2_SUPPORT_DIR}/${IDRIS2_SUPPORT}" ]; then \
		echo "ERROR: IDRIS2_SUPPORT_DIR is set but ${IDRIS2_SUPPORT_DIR}/${IDRIS2_SUPPORT} is missing"; \
		exit 1; \
	fi
endif

clean-support:
	@${MAKE} -C support clean

clean-libs:
	${JOBS_ENV} ${MAKE} -C libs/prelude clean
	${JOBS_ENV} ${MAKE} -C libs/base clean
	${JOBS_ENV} ${MAKE} -C libs/contrib clean
	${JOBS_ENV} ${MAKE} -C libs/network clean
	${JOBS_ENV} ${MAKE} -C libs/test clean
	${JOBS_ENV} ${MAKE} -C libs/linear clean
	${JOBS_ENV} ${MAKE} -C libs/papers clean

clean: clean-libs clean-support testenv-clean
	-${IDRIS2_BOOT} --clean ${IDRIS2_APP_IPKG}
	$(RM) src/IdrisPaths.idr
	${MAKE} -C tests clean
	$(RM) -r build

install: install-idris2 install-support install-libs
bootstrap-install: install-idris2 install-support install-bootstrap-libs

install-api: src/IdrisPaths.idr
	${IDRIS2_BOOT} --install ${IDRIS2_LIB_IPKG}

install-with-src-api: src/IdrisPaths.idr
	${IDRIS2_BOOT} --install-with-src ${IDRIS2_LIB_IPKG}

install-idris2:
	mkdir -p ${DESTDIR}${PREFIX}/bin/
	install ${TARGET} ${DESTDIR}${PREFIX}/bin
ifeq ($(OS), windows)
	-install ${TARGET}.cmd ${DESTDIR}${PREFIX}/bin
endif
	mkdir -p ${DESTDIR}${PREFIX}/bin/${NAME}_app
	install ${TARGETDIR}/${NAME}_app/* ${DESTDIR}${PREFIX}/bin/${NAME}_app

install-support:
	@${MAKE} -C support install

# The RefC support library built to find memory errors (see
# support/refc/Makefile), in place of the normal one under PREFIX.
install-support-refc-asan:
	@${MAKE} -C support/refc install-asan

install-bootstrap-libs:
	${JOBS_ENV} ${MAKE} -C libs/prelude install IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH} IDRIS2_INC_CGS=${IDRIS2_CG} IDRIS2_PREFIX=${IDRIS2_PREFIX}
	${JOBS_ENV} ${MAKE} -C libs/base install    IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH} IDRIS2_INC_CGS=${IDRIS2_CG} IDRIS2_PREFIX=${IDRIS2_PREFIX}
	${JOBS_ENV} ${MAKE} -C libs/linear install  IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH} IDRIS2_INC_CGS=${IDRIS2_CG} IDRIS2_PREFIX=${IDRIS2_PREFIX}
	${JOBS_ENV} ${MAKE} -C libs/network install IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH} IDRIS2_INC_CGS=${IDRIS2_CG} IDRIS2_PREFIX=${IDRIS2_PREFIX}

install-libs: install-bootstrap-libs
	${JOBS_ENV} ${MAKE} -C libs/contrib install IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH} IDRIS2_INC_CGS=${IDRIS2_CG} IDRIS2_PREFIX=${IDRIS2_PREFIX}
	${JOBS_ENV} ${MAKE} -C libs/test install IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH} IDRIS2_INC_CGS=${IDRIS2_CG} IDRIS2_PREFIX=${IDRIS2_PREFIX}

install-with-src-libs:
	${JOBS_ENV} ${MAKE} -C libs/prelude install-with-src IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH} IDRIS2_INC_CGS=${IDRIS2_CG}
	${JOBS_ENV} ${MAKE} -C libs/base install-with-src    IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH} IDRIS2_INC_CGS=${IDRIS2_CG}
	${JOBS_ENV} ${MAKE} -C libs/contrib install-with-src IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH} IDRIS2_INC_CGS=${IDRIS2_CG}
	${JOBS_ENV} ${MAKE} -C libs/network install-with-src IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH} IDRIS2_INC_CGS=${IDRIS2_CG}
	${JOBS_ENV} ${MAKE} -C libs/test install-with-src    IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH} IDRIS2_INC_CGS=${IDRIS2_CG}
	${JOBS_ENV} ${MAKE} -C libs/linear install-with-src  IDRIS2=${TARGET} IDRIS2_PATH=${IDRIS2_BOOT_PATH} IDRIS2_INC_CGS=${IDRIS2_CG}

install-libdocs: libdocs
	mkdir -p ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/prelude
	mkdir -p ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/base
	mkdir -p ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/contrib
	mkdir -p ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/network
	mkdir -p ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/test
	mkdir -p ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/linear
	cp -r libs/prelude/build/docs/* ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/prelude
	cp -r libs/base/build/docs/*    ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/base
	cp -r libs/contrib/build/docs/* ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/contrib
	cp -r libs/network/build/docs/* ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/network
	cp -r libs/test/build/docs/*    ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/test
	cp -r libs/linear/build/docs/*  ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/linear
	install -m 644 support/docs/*   ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs


.PHONY: bootstrap bootstrap-build bootstrap-c bootstrap-racket bootstrap-racket-build bootstrap-test bootstrap-clean

# Bootstrapping using SCHEME
#
# If you are bootstrapping using SCHEME _without building support_, support must have been explicitly
# built previously and you must set the IDRIS2_SUPPORT_DIR and IDRIS2_DATA environment variables to the
# locations of the lib and support folders (i.e. "/some/location/lib" and "/some/location/support").
bootstrap: support
	@if [ "$$(echo '(threaded?)' | $(SCHEME) --quiet)" = "#f" ] ; then \
		echo "ERROR: Chez is missing threading support" ; exit 1 ; fi
	mkdir -p bootstrap-build/idris2_app
	cp ${IDRIS2_SUPPORT_DIR}/${IDRIS2_SUPPORT} bootstrap-build/idris2_app/
	sed 's/libidris2_support.so/${IDRIS2_SUPPORT}/g; s|__PREFIX__|${IDRIS2_BOOT_PREFIX}|g' \
		bootstrap/idris2_app/idris2.ss \
		> bootstrap-build/idris2_app/idris2-boot.ss
	$(SHELL) ./bootstrap-stage1-chez.sh
	IDRIS2_CG="chez" $(SHELL) ./bootstrap-stage2.sh

# Bootstrapping using racket
bootstrap-racket: support
	mkdir -p bootstrap-build/idris2_app
	cp ${IDRIS2_SUPPORT_DIR}/${IDRIS2_SUPPORT} bootstrap-build/idris2_app/
	sed 's|__PREFIX__|${IDRIS2_BOOT_PREFIX}|g' \
		bootstrap/idris2_app/idris2.rkt \
		> bootstrap-build/idris2_app/idris2-boot.rkt
	$(SHELL) ./bootstrap-stage1-racket.sh
	IDRIS2_CG="racket" $(SHELL) ./bootstrap-stage2.sh

# Bootstrapping using only a C compiler, from the C code that the RefC backend
# generated for the compiler.  The final compiler is built with RefC too.
bootstrap-c: support
	mkdir -p bootstrap-build/idris2_app
	cp ${IDRIS2_SUPPORT_DIR}/${IDRIS2_SUPPORT} bootstrap-build/idris2_app/
	if [ -f bootstrap/idris2_app/idris2.c.xz ] ; then \
		xz -dc bootstrap/idris2_app/idris2.c.xz ; \
	else \
		cat bootstrap/idris2_app/idris2.c ; \
	fi | sed 's|__PREFIX__|${IDRIS2_BOOT_PREFIX}|g' \
		> bootstrap-build/idris2_app/idris2-boot.c
	CC="$(CC)" CPPFLAGS="$(CPPFLAGS)" LDFLAGS="$(LDFLAGS)" \
		$(SHELL) ./bootstrap-stage1-refc.sh
	IDRIS2_CG="refc" $(SHELL) ./bootstrap-stage2.sh

bootstrap-test:
	$(MAKE) test INTERACTIVE='' IDRIS2_PREFIX=${IDRIS2_BOOT_PREFIX}

ci-windows-bootstrap-test:
	$(MAKE) test except="idris2/repl005" INTERACTIVE='' IDRIS2_PREFIX=${IDRIS2_BOOT_PREFIX}

bootstrap-clean:
	$(RM) -r bootstrap-build


.PHONY: distclean

distclean: clean bootstrap-clean
	@find . -type f -name '*.ttc' -exec rm -f {} \;
	@find . -type f -name '*.ttm' -exec rm -f {} \;
	@find . -type f -name '*.ibc' -exec rm -f {} \;
