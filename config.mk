##### Options which a user might set before building go here #####

# Where to install idris2i-1 binaries and libraries (must be an absolute path)
PREFIX ?= $(HOME)/.idris2i-1

# For Windows targets. Set to 1 to support Windows 7.
OLD_WIN ?= 0

# Link time optimisation of the compiler when it is built with the RefC
# backend (the default code generator). 0 builds the C of the compiler quickly,
# with -O1 and no LTO. 1 builds it with -O2 -flto=auto (when the C compiler
# supports it): the compiler runs about 4% faster, but its C takes about twice
# as long to build. An IDRIS2I_1_CFLAGS or CFLAGS set in the environment takes
# precedence over both. `make bootstrap-c` builds the compiler that it leaves
# for installing with LTO=1 unless LTO is set (`make bootstrap-c LTO=0`).
LTO ?= 0

##################################################################

RANLIB ?= ranlib
AR ?= ar

CFLAGS += -Wall
CPPFLAGS := $(CPPFLAGS)
LDFLAGS := $(LDFLAGS)

MACHINE := $(shell $(CC) -dumpmachine)
ifneq (,$(findstring cygwin, $(MACHINE)))
	OS := windows
	SHLIB_SUFFIX := .dll
else ifneq (,$(findstring mingw, $(MACHINE)))
	OS := windows
	SHLIB_SUFFIX := .dll
else ifneq (,$(findstring windows, $(MACHINE)))
	OS := windows
	SHLIB_SUFFIX := .dll
else ifneq (,$(findstring darwin, $(MACHINE)))
	OS := darwin
	SHLIB_SUFFIX := .dylib
else ifneq (, $(findstring bsd, $(MACHINE)))
	OS := bsd
	SHLIB_SUFFIX := .so
else
	OS := linux
	SHLIB_SUFFIX := .so
endif

# Find homebrew's libgmp on ARM macs
ifneq (,$(wildcard ${HOMEBREW_PREFIX}/include/gmp.h))
	CPPFLAGS += -I${HOMEBREW_PREFIX}/include
	LDFLAGS += -L${HOMEBREW_PREFIX}/lib
endif

ifneq (, $(findstring freebsd, $(MACHINE)))
	CPPFLAGS += -I$(shell /sbin/sysctl -n user.localbase)/include
	LDFLAGS += -L$(shell /sbin/sysctl -n user.localbase)/lib
endif

ifneq ($(OS),windows)
	CFLAGS += -fPIC
else ifneq (, $(findstring NT-6.1,$(shell uname)))
	OLD_WIN = 1
endif

ifeq ($(OS),bsd)
	MAKE := gmake
else
	MAKE := make
endif

export OS MAKE OLD_WIN

# Add a custom.mk file to override any of the configurations
-include custom.mk
