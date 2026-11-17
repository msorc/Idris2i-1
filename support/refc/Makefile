include ../../config.mk

TARGET = libidris2_refc

LIBTARGET = $(TARGET).a

SRCS := $(wildcard *.c)
OBJS = $(SRCS:.c=.o)
DEPS = $(OBJS:.o=.d)

CFLAGS += -O2

ifeq ($(OLD_WIN), 1)
	CPPFLAGS += -D_OLD_WIN
endif

ifeq ($(OS), darwin)
	# ucontext.h is deprecated on macOS, but it is the only way to switch
	# between green threads there.
	CFLAGS += -Wno-deprecated-declarations
endif


.PHONY: all
all: build

.PHONY: build
build: $(LIBTARGET)

$(LIBTARGET): $(OBJS)
	$(AR) rc $@ $^
	$(RANLIB) $@

# Which headers each object file depends on.  The dependency file depends on
# them too, so that it is made again when a header starts to include another.
# -MP adds an empty rule for each header, so that a header that is removed or
# renamed makes the files that included it be made again, instead of an error.
ifeq (,$(filter clean cleandep,$(MAKECMDGOALS)))
-include $(DEPS)
endif

%.d: %.c
	@$(CPP) $(CPPFLAGS) $< -MM -MP -MT "$(@:.d=.o) $@" >$@.tmp && mv -f $@.tmp $@ || { $(RM) $@.tmp; false; }


.PHONY: clean
clean:
	$(RM) $(OBJS) $(LIBTARGET)
	$(RM) -r asan

.PHONY: cleandep
cleandep: clean
	$(RM) $(DEPS)


# A build that looks for memory errors (a value used after it was freed, by
# wrong reference counting, say): every value comes from malloc
# (IDRIS2_REFC_NO_POOLS), checked by AddressSanitizer and UBSan.
#   make install-support-refc-asan PREFIX=<prefix>
# (at the top of the repository) installs it in place of the normal library
# under a prefix that has the rest of an installation; compile the programs
# with
#   IDRIS2_PREFIX=<prefix> IDRIS2_CPPFLAGS=-DIDRIS2_REFC_NO_POOLS \
#   IDRIS2_CFLAGS="$(ASAN_FLAGS)" IDRIS2_LDFLAGS="$(ASAN_FLAGS)"
ASAN_FLAGS = -g -O1 -fno-omit-frame-pointer -fsanitize=address,undefined
ASAN_OBJS = $(addprefix asan/,$(OBJS))

asan/%.o: %.c $(wildcard *.h)
	@mkdir -p asan
	$(CC) $(CPPFLAGS) -DIDRIS2_REFC_NO_POOLS $(ASAN_FLAGS) -c $< -o $@

asan/$(LIBTARGET): $(ASAN_OBJS)
	$(AR) rc $@ $^
	$(RANLIB) $@

.PHONY: asan install-asan
asan: asan/$(LIBTARGET)

install-asan: asan
	mkdir -p ${DESTDIR}${PREFIX}/idris2-${IDRIS2_VERSION}/support/refc
	install -m 644 asan/$(LIBTARGET) *.h ${DESTDIR}${PREFIX}/idris2-${IDRIS2_VERSION}/support/refc

.PHONY: install
install: build
	mkdir -p ${DESTDIR}${PREFIX}/idris2-${IDRIS2_VERSION}/support/refc
	install -m 644 $(LIBTARGET) *.h ${DESTDIR}${PREFIX}/idris2-${IDRIS2_VERSION}/support/refc
