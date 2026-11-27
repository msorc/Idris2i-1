include config.mk

# Idris2i-1 executable used to bootstrap
export IDRIS2I_1_BOOT ?= idris2i-1

# Idris2i-1 executable we're building
NAME = idris2i-1
TARGETDIR = ${CURDIR}/build/exec
TARGET = ${TARGETDIR}/${NAME}

# The code generator that builds the compiler (refc or chez), with the
# compiler of IDRIS2I_1_BOOT.  It does not change the code generator that the
# compiler uses by default, which is RefC.
IDRIS2I_1_CG ?= refc

# The code generators that the libraries are also compiled with module by
# module, for the incremental builds of programs (IDRIS2I_1_INC_CGS of the
# compiler, see docs/source/backends/incremental.rst).  Only Chez has such
# builds.  By default, chez when the compiler is built with Chez (IDRIS2I_1_CG),
# or when the compiler in build/exec runs on Chez Scheme, as after `make
# bootstrap` (so that the `make install` that comes after it installs those
# files too); otherwise none, which saves the time it takes.
ifndef LIBS_INC_CGS
LIBS_INC_CGS := $(if $(filter chez,${IDRIS2I_1_CG})$(shell grep -Eqs '${NAME}_app/${NAME}(-boot)?\.so' ${TARGET} && echo chez),chez)
endif

# How many processes build the modules of the compiler and of the libraries in
# parallel (IDRIS2I_1_BUILD_JOBS of the compiler that builds them, which older
# compilers ignore): the number of processors, up to 16.  1 builds them one
# after the other.
IDRIS2I_1_JOBS ?= $(shell n=$$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1); [ "$$n" -gt 16 ] && n=16; echo $$n)
JOBS_ENV = IDRIS2I_1_BUILD_JOBS=${IDRIS2I_1_JOBS}

# The C preprocessor and linker flags, with the directories of GMP that
# config.mk adds on macOS (Homebrew) and FreeBSD, for the compilers that make
# runs and that compile C with RefC: the boot compiler that builds the
# compiler, and the compiler under test, which builds the test runner and the
# programs of the tests.  RefC reads them from the environment only
# (IDRIS2I_1_CPPFLAGS or CPPFLAGS, IDRIS2I_1_LDFLAGS or LDFLAGS), and they are not
# exported: the Makefiles of support/ read config.mk again, and would add the
# directories once more.  When they are empty, the environment is left as it
# is.
C_FLAGS_ENV = $(if ${CPPFLAGS},CPPFLAGS="${CPPFLAGS}") $(if ${LDFLAGS},LDFLAGS="${LDFLAGS}")

MAJOR=0
MINOR=1
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

export IDRIS2I_1_VERSION := ${MAJOR}.${MINOR}.${PATCH}
export NAME_VERSION := ${NAME}-${IDRIS2I_1_VERSION}
IDRIS2I_1_SUPPORT := libidris2i_1_support${SHLIB_SUFFIX}
IDRIS2I_1_APP_IPKG := idris2i-1.ipkg
IDRIS2I_1_LIB_IPKG := idris2i-1-api.ipkg

ifeq ($(OS), windows)
	# This produces D:/../.. style paths
	IDRIS2I_1_PREFIX ?= $(shell cygpath -m ${PREFIX})
	IDRIS2I_1_CURDIR := $(shell cygpath -m ${CURDIR})
	SEP := ;
	LINK_CMD = cp -rf
else
	IDRIS2I_1_PREFIX ?= ${PREFIX}
	IDRIS2I_1_CURDIR := ${CURDIR}
	SEP := :
	# -n: replace a link to a directory instead of putting a link in it
	LINK_CMD = ln -sfn
endif

IDRIS2I_1_SUPPORT_DIR ?= ${IDRIS2I_1_CURDIR}/support/c

TEST_PREFIX ?= ${IDRIS2I_1_CURDIR}/build/env

# The directory of the support library that the tests use (see test-support).
TEST_IDRIS2I_1_SUPPORT_DIR ?= ${TEST_PREFIX}/${NAME_VERSION}/lib

# Library and data paths for bootstrap-test
IDRIS2I_1_BOOT_PREFIX := ${IDRIS2I_1_CURDIR}/bootstrap-build

# The tls library (libs/tls) is optional: it is built, tested and installed
# only with OpenSSL 3 or later, as pkg-config finds it.  IDRIS2I_1_TLS=1 builds
# it anyway (and fails without OpenSSL), IDRIS2I_1_TLS=0 leaves it out.
PKG_CONFIG ?= pkg-config
ifndef IDRIS2I_1_TLS
IDRIS2I_1_TLS := $(shell ${PKG_CONFIG} --exists 'openssl >= 3' 2>/dev/null && echo 1 || echo 0)
TLS_SKIPPED_MSG = The tls library is skipped: ${PKG_CONFIG} does not find OpenSSL 3 (IDRIS2I_1_TLS=1 builds it anyway)
else
TLS_SKIPPED_MSG = The tls library is skipped: IDRIS2I_1_TLS=${IDRIS2I_1_TLS}
endif
TLS_LIB := $(if $(filter 1,${IDRIS2I_1_TLS}),tls)
# The http-tls library (libs/http-tls: HTTPS for the http library) goes with
# the tls library: built, tested and installed when it is.
HTTP_TLS_LIB := $(if ${TLS_LIB},http-tls)

# These are the library path in the build dir to be used during build
IDRIS2I_1_LIBRARIES = prelude base linear network contrib test http ${TLS_LIB} ${HTTP_TLS_LIB}

IDRIS2I_1_BOOT_PATH =
$(foreach library,$(IDRIS2I_1_LIBRARIES),$(eval IDRIS2I_1_BOOT_PATH := $(IDRIS2I_1_BOOT_PATH)$(IDRIS2I_1_CURDIR)/libs/$(library)/build/ttc$(SEP)))
export IDRIS2I_1_BOOT_PATH := "$(IDRIS2I_1_BOOT_PATH)"

export SCHEME

.PHONY: all idris2i-1-exec libdocs testenv testenv-clean support clean-support clean FORCE
.PHONY: libs libs-core libs-rest prelude base linear contrib network test-lib papers http tls tls-skipped http-tls
.PHONY: api-snapshots api-check

all:
	${MAKE} ${TARGET}
	${MAKE} libs

idris2i-1-exec: ${TARGET}

# With RefC, the generated C is optimised unless told otherwise (older
# compilers, like the one of bootstrap-c, do not do it by default).  The
# compiler is compiled in parts in parallel.  A plain make is quick: -O1, no
# link time optimisation.  With LTO=1 it is -O2, and -flto=auto when the C
# compiler has it: that gives back the inlining across the parts (the compiler
# runs about 4% faster) but doubles the time of the C build.  An IDRIS2I_1_CFLAGS
# or CFLAGS from the user takes precedence.
#
# RefC builds a single binary: it is given the layout of the Scheme backends,
# a launcher next to an idris2i-1_app directory.  The compiler skips compiling an
# executable that is up to date: then ${TARGET} is the launcher already (a
# script), and the binary is where it was moved to.
#
# The C support library (support/c) that the RefC binary links, and its
# headers, are those of this tree, which the sources of the compiler are
# written for (a compiler on Chez loads the one of this tree too, copied
# below): IDRIS2I_1_LIBS gives the library, and IDRIS2I_1_DATA a directory with
# only the `c` headers.  The RefC runtime (support/refc) stays the one of
# IDRIS2I_1_BOOT, as it must match the code generator that writes the C.
SUPPORT_C_DATA = ${IDRIS2I_1_CURDIR}/build/support-c-data
${TARGET}: support src/IdrisPaths.idr
ifeq ($(IDRIS2I_1_CG), refc)
	mkdir -p ${SUPPORT_C_DATA}
	${LINK_CMD} ${IDRIS2I_1_CURDIR}/support/c ${SUPPORT_C_DATA}/c
	IDRIS2I_1_LIBS="${IDRIS2I_1_SUPPORT_DIR}$${IDRIS2I_1_LIBS:+${SEP}$$IDRIS2I_1_LIBS}"; \
	IDRIS2I_1_DATA="${SUPPORT_C_DATA}$${IDRIS2I_1_DATA:+${SEP}$$IDRIS2I_1_DATA}"; \
	export IDRIS2I_1_LIBS IDRIS2I_1_DATA; \
	DEFAULT_CFLAGS=-O1; \
	if [ "${LTO}" = 1 ]; then \
		DEFAULT_CFLAGS=-O2; \
		if sh bootstrap/cc-has-lto.sh "$${IDRIS2I_1_CC:-$${CC:-cc}}"; then DEFAULT_CFLAGS="-O2 -flto=auto"; fi; \
	fi; \
	IDRIS2I_1_CG="${IDRIS2I_1_CG}" ${C_FLAGS_ENV} IDRIS2I_1_CFLAGS="$${IDRIS2I_1_CFLAGS:-$${CFLAGS:-$$DEFAULT_CFLAGS}}" ${JOBS_ENV} ${IDRIS2I_1_BOOT} --build ${IDRIS2I_1_APP_IPKG}
else
	IDRIS2I_1_CG="${IDRIS2I_1_CG}" ${JOBS_ENV} ${IDRIS2I_1_BOOT} --build ${IDRIS2I_1_APP_IPKG}
endif
ifeq ($(IDRIS2I_1_CG), refc)
	mkdir -p ${TARGETDIR}/${NAME}_app
	if [ "$$(head -c 2 ${TARGET})" != '#!' ]; then \
		mv -f ${TARGET} ${TARGETDIR}/${NAME}_app/${NAME}; \
	fi
	install bootstrap/idris2i-1-refc.sh ${TARGET}
endif
	cp ${IDRIS2I_1_SUPPORT_DIR}/${IDRIS2I_1_SUPPORT} ${TARGETDIR}/${NAME}_app/${IDRIS2I_1_SUPPORT}

# We use FORCE to always regenerate IdrisPaths so that the git SHA1 info is
# always up to date.  The file is only replaced when its content changes: the
# compiler rebuilds the modules that import it when its modification time does.
src/IdrisPaths.idr: FORCE
	{ echo "-- @""generated"; \
	  echo 'module IdrisPaths'; \
	  echo 'export idrisVersion : ((Nat,Nat,Nat), String); idrisVersion = ((${MAJOR},${MINOR},${PATCH}), "${VERSION_TAG}")'; \
	  echo 'export yprefix : String; yprefix="${IDRIS2I_1_PREFIX}"'; \
	} > src/IdrisPaths.idr.tmp
	if cmp -s src/IdrisPaths.idr.tmp src/IdrisPaths.idr; then \
		$(RM) src/IdrisPaths.idr.tmp; \
	else \
		mv -f src/IdrisPaths.idr.tmp src/IdrisPaths.idr; \
	fi

FORCE:

# The libraries, with the libraries they import (the depends of their ipkg,
# and what their modules import from the others):
#   prelude
#   base:    prelude
#   linear:  base
#   contrib: base
#   network: base linear
#   test:    base contrib
#   papers:  base linear contrib
#   http:    base contrib network
#   tls:     base network (optional: see IDRIS2I_1_TLS)
#   http-tls: base contrib network http tls (with tls only)
#
# The libraries that do not depend on each other are built at the same time,
# LIBS_PARALLEL of them at most (1 builds them one after the other).  This is
# only done with the RefC backend: the incremental builds of the Scheme
# backends write shared files, and fail when run in parallel.  Each of the
# libraries that run together checks its modules with half of IDRIS2I_1_JOBS
# processes, so that the machine is not oversubscribed (when make runs one
# thing at a time, as in `make linear`, a library has all of them), and make
# keeps the output of a library together when it can (GNU make 4 and later).
# When make runs in parallel already (make -jN), that is left to it.
LIBS_PARALLEL ?= $(if $(filter refc,${IDRIS2I_1_CG}),3,1)
ifeq (${LIBS_PARALLEL},1)
LIBS_JOBS_ENV = ${JOBS_ENV}
LIBS_MAKEFLAGS =
else
LIBS_JOBS_ENV = $(if $(filter-out -j1,$(filter -j%,${MAKEFLAGS})),IDRIS2I_1_BUILD_JOBS=$(shell echo $$(( (${IDRIS2I_1_JOBS} + 1) / 2 ))),${JOBS_ENV})
LIBS_MAKEFLAGS = $(if $(filter -j%,${MAKEFLAGS}),,-j${LIBS_PARALLEL} $(if $(filter output-sync,${.FEATURES}),--output-sync=target))
endif

# The libraries that all the others import (see libs below: they are already
# built when the others are, and are not checked again then).
ifdef LIBS_CORE_DONE
LIBS_CORE =
else
LIBS_CORE = prelude base
endif

prelude:
	${JOBS_ENV} ${MAKE} -C libs/prelude IDRIS2I_1=${TARGET} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}

base: prelude
	${JOBS_ENV} ${MAKE} -C libs/base IDRIS2I_1=${TARGET} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}

linear: ${LIBS_CORE}
	${LIBS_JOBS_ENV} ${MAKE} -C libs/linear IDRIS2I_1=${TARGET} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}

contrib: ${LIBS_CORE}
	${LIBS_JOBS_ENV} ${MAKE} -C libs/contrib IDRIS2I_1=${TARGET} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}

network: ${LIBS_CORE} linear
	${LIBS_JOBS_ENV} ${MAKE} -C libs/network IDRIS2I_1=${TARGET} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}

test-lib: ${LIBS_CORE} contrib
	${LIBS_JOBS_ENV} ${MAKE} -C libs/test IDRIS2I_1=${TARGET} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}

papers: ${LIBS_CORE} linear contrib
	${LIBS_JOBS_ENV} ${MAKE} -C libs/papers IDRIS2I_1=${TARGET} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}

http: ${LIBS_CORE} contrib network
	${LIBS_JOBS_ENV} ${MAKE} -C libs/http IDRIS2I_1=${TARGET} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}

tls: ${LIBS_CORE} network
	${LIBS_JOBS_ENV} ${MAKE} -C libs/tls IDRIS2I_1=${TARGET} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}

tls-skipped:
	@echo "${TLS_SKIPPED_MSG}"

http-tls: ${LIBS_CORE} contrib network http tls
	${LIBS_JOBS_ENV} ${MAKE} -C libs/http-tls IDRIS2I_1=${TARGET} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}

bootstrap-libs: prelude base linear network

# prelude and base first, one after the other, as everything depends on them;
# then the others, in this order when they are built one after the other.
libs-core: prelude base
libs-rest: contrib linear network test-lib papers http $(if ${TLS_LIB},tls http-tls,tls-skipped)

libs:
	${MAKE} libs-core
	${MAKE} ${LIBS_MAKEFLAGS} LIBS_CORE_DONE=1 libs-rest

libdocs:
	${JOBS_ENV} ${MAKE} -C libs/prelude docs IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}
	${JOBS_ENV} ${MAKE} -C libs/base docs IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}
	${JOBS_ENV} ${MAKE} -C libs/contrib docs IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}
	${JOBS_ENV} ${MAKE} -C libs/network docs IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}
	${JOBS_ENV} ${MAKE} -C libs/test docs IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}
	${JOBS_ENV} ${MAKE} -C libs/linear docs IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}
	${JOBS_ENV} ${MAKE} -C libs/http docs IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}
ifneq (${TLS_LIB},)
	${JOBS_ENV} ${MAKE} -C libs/tls docs IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}
	${JOBS_ENV} ${MAKE} -C libs/http-tls docs IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH}
endif

# The public API of the libraries in API_LIBS, as printed by `idris2i-1
# --dump-api`, is committed in libs/api/<lib>.api.  `api-snapshots` writes
# these files again from the libraries as they are now (built by `make libs`);
# `api-check` fails, showing the difference, when a library's API is no longer
# the one of its file.
API_LIBS ?= prelude base contrib http ${TLS_LIB} ${HTTP_TLS_LIB}
API_DIR = ${IDRIS2I_1_CURDIR}/libs/api
API_BUILD_DIR = ${IDRIS2I_1_CURDIR}/build/api

api-snapshots:
	@mkdir -p ${API_DIR}
	@for lib in ${API_LIBS}; do \
	  echo "Writing libs/api/$$lib.api"; \
	  ( cd libs/$$lib && IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} ${TARGET} --dump-api $$lib.ipkg ) > ${API_DIR}/$$lib.api.new \
	    && mv ${API_DIR}/$$lib.api.new ${API_DIR}/$$lib.api \
	    || { cat ${API_DIR}/$$lib.api.new; rm -f ${API_DIR}/$$lib.api.new; exit 1; }; \
	done

api-check:
	@mkdir -p ${API_BUILD_DIR}
	@status=0; for lib in ${API_LIBS}; do \
	  ( cd libs/$$lib && IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} ${TARGET} --dump-api $$lib.ipkg ) > ${API_BUILD_DIR}/$$lib.api \
	    || { cat ${API_BUILD_DIR}/$$lib.api; exit 1; }; \
	  if diff -u -F "^module " -L libs/api/$$lib.api -L "$$lib now" ${API_DIR}/$$lib.api ${API_BUILD_DIR}/$$lib.api; then \
	    echo "$$lib: the API is the one of libs/api/$$lib.api"; \
	  else \
	    echo "$$lib: the API is no longer the one of libs/api/$$lib.api (- before, + now)."; \
	    echo "If the change is intended, run \`${MAKE} api-snapshots\` and commit libs/api."; \
	    status=1; \
	  fi; \
	done; exit $$status

${TEST_PREFIX}/${NAME_VERSION} :
	${LINK_CMD} ${IDRIS2I_1_CURDIR}/libs/prelude/build/ttc ${TEST_PREFIX}/${NAME_VERSION}/prelude-${IDRIS2I_1_VERSION}
	${LINK_CMD} ${IDRIS2I_1_CURDIR}/libs/base/build/ttc    ${TEST_PREFIX}/${NAME_VERSION}/base-${IDRIS2I_1_VERSION}
	${LINK_CMD} ${IDRIS2I_1_CURDIR}/libs/linear/build/ttc  ${TEST_PREFIX}/${NAME_VERSION}/linear-${IDRIS2I_1_VERSION}
	${LINK_CMD} ${IDRIS2I_1_CURDIR}/libs/network/build/ttc ${TEST_PREFIX}/${NAME_VERSION}/network-${IDRIS2I_1_VERSION}
	${LINK_CMD} ${IDRIS2I_1_CURDIR}/libs/contrib/build/ttc ${TEST_PREFIX}/${NAME_VERSION}/contrib-${IDRIS2I_1_VERSION}
	${LINK_CMD} ${IDRIS2I_1_CURDIR}/libs/test/build/ttc    ${TEST_PREFIX}/${NAME_VERSION}/test-${IDRIS2I_1_VERSION}
	${LINK_CMD} ${IDRIS2I_1_CURDIR}/libs/http/build/ttc    ${TEST_PREFIX}/${NAME_VERSION}/http-${IDRIS2I_1_VERSION}
ifneq (${TLS_LIB},)
	${LINK_CMD} ${IDRIS2I_1_CURDIR}/libs/tls/build/ttc     ${TEST_PREFIX}/${NAME_VERSION}/tls-${IDRIS2I_1_VERSION}
	${LINK_CMD} ${IDRIS2I_1_CURDIR}/libs/http-tls/build/ttc ${TEST_PREFIX}/${NAME_VERSION}/http-tls-${IDRIS2I_1_VERSION}
else
	@$(RM) ${TEST_PREFIX}/${NAME_VERSION}/tls-${IDRIS2I_1_VERSION}
	@$(RM) ${TEST_PREFIX}/${NAME_VERSION}/http-tls-${IDRIS2I_1_VERSION}
	@echo "${TLS_SKIPPED_MSG}"
endif

.PHONY: ${TEST_PREFIX}/${NAME_VERSION}

# The support libraries that the tests use, installed under TEST_PREFIX.  This
# always goes through support (which rebuilds what changed) and reinstalls: a
# check on the installed files would not see a change of the sources.  The
# files are installed with their modification times (install -p), so that
# reinstalling the same files does not make the executables that were built
# with them, like the test runner, look out of date.  When
# TEST_IDRIS2I_1_SUPPORT_DIR points elsewhere, to support libraries that were
# built beforehand, they are only checked for, as with IDRIS2I_1_SUPPORT_DIR
# (the tests find them through TEST_IDRIS2I_1_LIBS and TEST_IDRIS2I_1_DATA, see
# tests/testutils.sh).
ifeq (${TEST_IDRIS2I_1_SUPPORT_DIR},${TEST_PREFIX}/${NAME_VERSION}/lib)
test-support:
	${MAKE} install-support PREFIX=${TEST_PREFIX}
else
test-support:
	@if [ ! -f "${TEST_IDRIS2I_1_SUPPORT_DIR}/${IDRIS2I_1_SUPPORT}" ]; then \
		echo "ERROR: TEST_IDRIS2I_1_SUPPORT_DIR is set but ${TEST_IDRIS2I_1_SUPPORT_DIR}/${IDRIS2I_1_SUPPORT} is missing"; \
		exit 1; \
	fi
endif

testenv: test-support
	mkdir -p ${TEST_PREFIX}/${NAME_VERSION}
	@${MAKE} ${TEST_PREFIX}/${NAME_VERSION}
	@${MAKE} -C tests testbin IDRIS2I_1=${TARGET} IDRIS2I_1_PREFIX=${TEST_PREFIX} ${C_FLAGS_ENV}

testenv-clean:
	$(RM) -r ${TEST_PREFIX}/${NAME_VERSION}

ci-ubuntu-test: test
ci-macos-test: test
ci-windows-test:
	@${MAKE} test except="idris2i-1/repl005"

test: testenv
	@echo
	@echo "NOTE: \`${MAKE} test\` does not rebuild Idris or the libraries packaged with it; to do that run \`${MAKE}\`"
	@if [ ! -x "${TARGET}" ]; then echo "ERROR: Missing IDRIS2I_1 executable. Cannot run tests!\n"; exit 1; fi
	@echo
	@${MAKE} -C tests only=$(only) except=$(except) IDRIS2I_1=${TARGET} IDRIS2I_1_PREFIX=${TEST_PREFIX} ${C_FLAGS_ENV}


retest: testenv
	@echo
	@echo "NOTE: \`${MAKE} retest\` does not rebuild Idris or the libraries packaged with it; to do that run \`${MAKE}\`"
	@if [ ! -x "${TARGET}" ]; then echo "ERROR: Missing IDRIS2I_1 executable. Cannot run tests!\n"; exit 1; fi
	@echo
	@${MAKE} -C tests retest only=$(only) IDRIS2I_1=${TARGET} IDRIS2I_1_PREFIX=${TEST_PREFIX} ${C_FLAGS_ENV}

test-installed:
	@${MAKE} -C tests testbin      IDRIS2I_1=$(IDRIS2I_1_PREFIX)/bin/idris2i-1 IDRIS2I_1_PREFIX=${IDRIS2I_1_PREFIX} ${C_FLAGS_ENV}
	@${MAKE} -C tests only=$(only) IDRIS2I_1=$(IDRIS2I_1_PREFIX)/bin/idris2i-1 IDRIS2I_1_PREFIX=${IDRIS2I_1_PREFIX} ${C_FLAGS_ENV}

# Build the support libraries (in support/, where the Makefiles rebuild what
# changed since the last time, so this does not use the file as a target).
# When IDRIS2I_1_SUPPORT_DIR points elsewhere, to support libraries that were
# built beforehand (see bootstrap), they are only checked for.
ifeq (${IDRIS2I_1_SUPPORT_DIR},${IDRIS2I_1_CURDIR}/support/c)
support:
	@${MAKE} -C support
else
support:
	@if [ ! -f "${IDRIS2I_1_SUPPORT_DIR}/${IDRIS2I_1_SUPPORT}" ]; then \
		echo "ERROR: IDRIS2I_1_SUPPORT_DIR is set but ${IDRIS2I_1_SUPPORT_DIR}/${IDRIS2I_1_SUPPORT} is missing"; \
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
	${JOBS_ENV} ${MAKE} -C libs/http clean
	${JOBS_ENV} ${MAKE} -C libs/tls clean
	${JOBS_ENV} ${MAKE} -C libs/http-tls clean

clean: clean-libs clean-support testenv-clean
	-${IDRIS2I_1_BOOT} --clean ${IDRIS2I_1_APP_IPKG}
	$(RM) src/IdrisPaths.idr
	${MAKE} -C tests clean
	$(RM) -r build

install: install-idris2i-1 install-support install-libs
bootstrap-install: install-idris2i-1 install-support install-bootstrap-libs

install-api: src/IdrisPaths.idr
	${IDRIS2I_1_BOOT} --install ${IDRIS2I_1_LIB_IPKG}

install-with-src-api: src/IdrisPaths.idr
	${IDRIS2I_1_BOOT} --install-with-src ${IDRIS2I_1_LIB_IPKG}

install-idris2i-1:
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
	${JOBS_ENV} ${MAKE} -C libs/prelude install IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PREFIX=${IDRIS2I_1_PREFIX}
	${JOBS_ENV} ${MAKE} -C libs/base install    IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PREFIX=${IDRIS2I_1_PREFIX}
	${JOBS_ENV} ${MAKE} -C libs/linear install  IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PREFIX=${IDRIS2I_1_PREFIX}
	${JOBS_ENV} ${MAKE} -C libs/network install IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PREFIX=${IDRIS2I_1_PREFIX}

install-libs: install-bootstrap-libs
	${JOBS_ENV} ${MAKE} -C libs/contrib install IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PREFIX=${IDRIS2I_1_PREFIX}
	${JOBS_ENV} ${MAKE} -C libs/test install IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PREFIX=${IDRIS2I_1_PREFIX}
	${JOBS_ENV} ${MAKE} -C libs/http install IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PREFIX=${IDRIS2I_1_PREFIX}
ifneq (${TLS_LIB},)
	${JOBS_ENV} ${MAKE} -C libs/tls install IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PREFIX=${IDRIS2I_1_PREFIX}
	${JOBS_ENV} ${MAKE} -C libs/http-tls install IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS} IDRIS2I_1_PREFIX=${IDRIS2I_1_PREFIX}
else
	@echo "${TLS_SKIPPED_MSG}"
endif

install-with-src-libs:
	${JOBS_ENV} ${MAKE} -C libs/prelude install-with-src IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS}
	${JOBS_ENV} ${MAKE} -C libs/base install-with-src    IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS}
	${JOBS_ENV} ${MAKE} -C libs/contrib install-with-src IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS}
	${JOBS_ENV} ${MAKE} -C libs/network install-with-src IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS}
	${JOBS_ENV} ${MAKE} -C libs/test install-with-src    IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS}
	${JOBS_ENV} ${MAKE} -C libs/linear install-with-src  IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS}
	${JOBS_ENV} ${MAKE} -C libs/http install-with-src    IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS}
ifneq (${TLS_LIB},)
	${JOBS_ENV} ${MAKE} -C libs/tls install-with-src     IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS}
	${JOBS_ENV} ${MAKE} -C libs/http-tls install-with-src IDRIS2I_1=${TARGET} IDRIS2I_1_PATH=${IDRIS2I_1_BOOT_PATH} IDRIS2I_1_INC_CGS=${LIBS_INC_CGS}
endif

install-libdocs: libdocs
	mkdir -p ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/prelude
	mkdir -p ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/base
	mkdir -p ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/contrib
	mkdir -p ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/network
	mkdir -p ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/test
	mkdir -p ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/linear
	mkdir -p ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/http
	cp -r libs/prelude/build/docs/* ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/prelude
	cp -r libs/base/build/docs/*    ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/base
	cp -r libs/contrib/build/docs/* ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/contrib
	cp -r libs/network/build/docs/* ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/network
	cp -r libs/test/build/docs/*    ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/test
	cp -r libs/linear/build/docs/*  ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/linear
	cp -r libs/http/build/docs/*    ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/http
ifneq (${TLS_LIB},)
	mkdir -p ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/tls
	cp -r libs/tls/build/docs/*     ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/tls
	mkdir -p ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/http-tls
	cp -r libs/http-tls/build/docs/* ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs/http-tls
endif
	install -m 644 support/docs/*   ${DESTDIR}${PREFIX}/${NAME_VERSION}/docs


.PHONY: bootstrap bootstrap-build bootstrap-c bootstrap-test bootstrap-clean

# Bootstrapping using SCHEME
#
# If you are bootstrapping using SCHEME _without building support_, support must have been explicitly
# built previously and you must set the IDRIS2I_1_SUPPORT_DIR and IDRIS2I_1_DATA environment variables to the
# locations of the lib and support folders (i.e. "/some/location/lib" and "/some/location/support").
bootstrap: support
	@if [ "$$(echo '(threaded?)' | $(SCHEME) --quiet)" = "#f" ] ; then \
		echo "ERROR: Chez is missing threading support" ; exit 1 ; fi
	mkdir -p bootstrap-build/idris2i-1_app
	cp ${IDRIS2I_1_SUPPORT_DIR}/${IDRIS2I_1_SUPPORT} bootstrap-build/idris2i-1_app/
	@# The first line names the Chez Scheme of the machine that generated the
	@# file (#!/usr/bin/chez --program), and Chez copies it into the .so, which
	@# the compiler runs again to build modules in parallel: name ours instead.
	scheme_path=$$(command -v '${SCHEME}') || { echo "ERROR: cannot find ${SCHEME}"; exit 1; }; \
	sed "1s|^#!.*|#!$$scheme_path --program|; s/libidris2i_1_support.so/${IDRIS2I_1_SUPPORT}/g; s|__PREFIX__|${IDRIS2I_1_BOOT_PREFIX}|g" \
		bootstrap/idris2i-1_app/idris2i-1.ss \
		> bootstrap-build/idris2i-1_app/idris2i-1-boot.ss
	$(SHELL) ./bootstrap-stage1-chez.sh
	IDRIS2I_1_CG="chez" $(SHELL) ./bootstrap-stage2.sh

# Bootstrapping using only a C compiler, from the C code that the RefC backend
# generated for the compiler.  The final compiler is built with RefC too.
bootstrap-c: support
	mkdir -p bootstrap-build/idris2i-1_app
	cp ${IDRIS2I_1_SUPPORT_DIR}/${IDRIS2I_1_SUPPORT} bootstrap-build/idris2i-1_app/
	@src=bootstrap/idris2i-1_app/idris2i-1.c; out=bootstrap-build/idris2i-1_app/idris2i-1-boot.c; \
	$(RM) $$out $$out.tmp $$out.xz-tmp; \
	if [ -f $$src.xz ]; then \
		if ! command -v xz >/dev/null 2>&1; then \
			echo "ERROR: xz is needed to decompress $$src.xz: install it (the package is usually xz or xz-utils)"; \
			exit 1; \
		fi; \
		echo "xz -dc $$src.xz > $$out.xz-tmp"; \
		if ! xz -dc $$src.xz > $$out.xz-tmp; then \
			$(RM) $$out.xz-tmp; \
			echo "ERROR: could not decompress $$src.xz"; \
			exit 1; \
		fi; \
		src=$$out.xz-tmp; \
	fi; \
	echo "sed 's|__PREFIX__|${IDRIS2I_1_BOOT_PREFIX}|g' $$src > $$out"; \
	sed 's|__PREFIX__|${IDRIS2I_1_BOOT_PREFIX}|g' $$src > $$out.tmp && mv -f $$out.tmp $$out; \
	status=$$?; $(RM) $$out.tmp $$out.xz-tmp; exit $$status
	CC="$(CC)" CPPFLAGS="$(CPPFLAGS)" LDFLAGS="$(LDFLAGS)" \
		$(SHELL) ./bootstrap-stage1-refc.sh
	IDRIS2I_1_CG="refc" $(SHELL) ./bootstrap-stage2.sh

bootstrap-test:
	$(MAKE) test INTERACTIVE='' IDRIS2I_1_PREFIX=${IDRIS2I_1_BOOT_PREFIX}

ci-windows-bootstrap-test:
	$(MAKE) test except="idris2i-1/repl005" INTERACTIVE='' IDRIS2I_1_PREFIX=${IDRIS2I_1_BOOT_PREFIX}

bootstrap-clean:
	$(RM) -r bootstrap-build


.PHONY: distclean

distclean: clean bootstrap-clean
	@find . -type f -name '*.ttc' -exec rm -f {} \;
	@find . -type f -name '*.ttm' -exec rm -f {} \;
	@find . -type f -name '*.ibc' -exec rm -f {} \;


.PHONY: help

define HELP_TEXT
Usage: make [TARGET...] [VARIABLE=value...]

Build
  all                    The compiler, then the libraries (the default)
  idris2i-1-exec            The compiler only, as build/exec/${NAME}
  libs                   The libraries, with the compiler in build/exec
  support                The C support libraries
  libdocs                The documentation of the libraries
  api-snapshots          Write the public API of the libraries in API_LIBS to libs/api

Bootstrap, without an existing Idris2i-1 (see INSTALL.md)
  bootstrap-c            With a C compiler only, from bootstrap/idris2i-1_app/idris2i-1.c.xz
  bootstrap              With Chez Scheme (SCHEME=chez), from idris2i-1.ss
  bootstrap-test         Run the tests with the bootstrapped compiler

Test
  test                   Run the tests (does not rebuild the compiler or the libraries)
  retest                 Run the tests that failed the last time
  test-installed         Run the tests with the installed compiler
  api-check              Fail when the API of a library in API_LIBS is not the one in libs/api

Install, under PREFIX
  install                The compiler, the support libraries and the libraries
  install-api            The compiler as a library (idris2i-1-api)
  install-with-src-api   The same, with its sources
  install-with-src-libs  The libraries with their sources
  install-libdocs        The documentation of the libraries

Clean
  clean                  What the build made: compiler, libraries, support, test environment
  clean-libs             The libraries only
  clean-support          The support libraries only
  bootstrap-clean        bootstrap-build/
  distclean              All of the above and every .ttc, .ttm and .ibc file

Variables (current value)
  PREFIX=${PREFIX}
                         Where to install
  IDRIS2I_1_BOOT=${IDRIS2I_1_BOOT}
                         The Idris2i-1 that builds the compiler
  IDRIS2I_1_CG=${IDRIS2I_1_CG}
                         The code generator the compiler is built with (refc, chez)
  IDRIS2I_1_JOBS=${IDRIS2I_1_JOBS}
                         Modules to build in parallel, 1 for one after the other
  IDRIS2I_1_CC_JOBS         RefC: C compilers that compile the compiler's C in parallel
                         (environment, default: the number of processors, up to 16)
  LIBS_PARALLEL=${LIBS_PARALLEL}
                         Libraries to build in parallel, 1 for one after the other
  LIBS_INC_CGS=${LIBS_INC_CGS}
                         Code generators that also compile the libraries for incremental
                         builds (only chez has them; by default chez for a compiler on Chez)
  LTO=${LTO}
                         1 builds the compiler's C with -O2 and link-time optimisation:
                         slower to build, faster to run (bootstrap-c defaults to 1)
  CFLAGS, IDRIS2I_1_CFLAGS  C flags for the compiler's own C code, in place of the default
  BOOT_CFLAGS            C flags for the first stage of bootstrap-c (environment, default -O1)
  BOOT_JOBS              C compilers for the first stage of bootstrap-c (environment, default:
                         the number of processors, up to 16 and 1 per 1.5 GB of available memory)
  BOOT_PARTS             Parts that BOOT_JOBS compile (environment, default 16 or BOOT_JOBS)
  API_LIBS=${API_LIBS}
                         The libraries whose API api-snapshots and api-check compare
  IDRIS2I_1_TLS=${IDRIS2I_1_TLS}
                         1 builds, tests and installs the tls and http-tls libraries (they need OpenSSL 3),
                         0 leaves them out (by default 1 when pkg-config finds OpenSSL 3)
  only=, except=         Limit the tests, e.g. make test only=refc except=refc/doubles
endef

help:
	@: $(info ${HELP_TEXT})
