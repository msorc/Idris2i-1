# The C part of the tls library: a static archive for the RefC back end and
# a shared library for the Chez back end, both linked with
# OpenSSL 3 as pkg-config finds it.

include ../../../config.mk

PKG_CONFIG ?= pkg-config

TARGET = libidris2i_1_tls
LIBTARGET = $(TARGET).a
DYLIBTARGET = $(TARGET)$(SHLIB_SUFFIX)

OPENSSL_CFLAGS := $(shell $(PKG_CONFIG) --cflags openssl 2>/dev/null)
OPENSSL_LIBS := $(shell $(PKG_CONFIG) --libs openssl 2>/dev/null || echo -lssl -lcrypto)

CFLAGS += -O2 -Wextra
CPPFLAGS += $(OPENSSL_CFLAGS)

.PHONY: all
all: $(LIBTARGET) $(DYLIBTARGET)

idris_tls.o: idris_tls.c idris_tls.h
	$(CC) $(CFLAGS) $(CPPFLAGS) -c idris_tls.c -o $@

$(LIBTARGET): idris_tls.o
	$(AR) rc $@ $^
	$(RANLIB) $@

$(DYLIBTARGET): idris_tls.o
	$(CC) $(CFLAGS) -shared -o $@ $^ $(LDFLAGS) $(OPENSSL_LIBS) -lpthread

.PHONY: clean
clean:
	$(RM) idris_tls.o $(LIBTARGET) $(DYLIBTARGET)
