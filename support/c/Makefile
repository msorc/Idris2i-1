include ../../config.mk

TARGET = libidris2i_1_support

LIBTARGET = $(TARGET).a
DYLIBTARGET = $(TARGET)$(SHLIB_SUFFIX)

SRCS := $(wildcard *.c)
OBJS = $(SRCS:.c=.o)
DEPS = $(OBJS:.o=.d)

CFLAGS += -O2

# Every function and variable in a section of its own, so that the linker
# of a RefC program (with --gc-sections, see src/Compiler/RefC/CC.idr)
# leaves out the parts of the library that the program does not use.
CFLAGS += -ffunction-sections -fdata-sections

ifeq ($(OS), windows)
	SRCS += windows/win_utils.c windows/win_hack.c
	CPPFLAGS += -DWIN32_LEAN_AND_MEAN
	LDFLAGS += -lws2_32
ifeq ($(OLD_WIN), 1)
	CPPFLAGS += -D_OLD_WIN
endif
endif


.PHONY: all
all: build

.PHONY: build
build: $(LIBTARGET) $(DYLIBTARGET)

$(LIBTARGET): $(OBJS)
	$(AR) rc $@ $^
	$(RANLIB) $@

$(DYLIBTARGET): $(OBJS)
	$(CC) $(CFLAGS) $(CPPFLAGS) -shared -o $@ $^ $(LDFLAGS)

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
	$(RM) $(OBJS) $(DYLIBTARGET) $(LIBTARGET)

.PHONY: cleandep
cleandep: clean
	$(RM) $(DEPS)


.PHONY: install
install: build
	mkdir -p ${DESTDIR}${PREFIX}/idris2i-1-${IDRIS2I_1_VERSION}/lib
	mkdir -p ${DESTDIR}${PREFIX}/idris2i-1-${IDRIS2I_1_VERSION}/support/c
	install -p -m 755 $(DYLIBTARGET) ${DESTDIR}${PREFIX}/idris2i-1-${IDRIS2I_1_VERSION}/lib
	install -p -m 644 $(LIBTARGET)   ${DESTDIR}${PREFIX}/idris2i-1-${IDRIS2I_1_VERSION}/lib
	install -p -m 644 *.h            ${DESTDIR}${PREFIX}/idris2i-1-${IDRIS2I_1_VERSION}/support/c
