// ---------------------------------------------------------------------------
// Backtraces of a program that dies of a fatal error.
//
// When they are on (IDRIS2_REFC_BACKTRACE=1, or by default in a program
// compiled with `--directive refc-backtrace`), a program that dies of
// `idris_crash`, of a missing case in partial code, of a division by zero, or
// of SIGSEGV, SIGBUS, SIGFPE, SIGILL or SIGABRT (from foreign code, or a stack
// overflow) prints the functions of the thread that died on stderr, after the
// message of the error, the innermost first.
//
// The stack is walked by the unwinder of the C compiler (_Unwind_Backtrace,
// which reads the .eh_frame tables that GCC and Clang put in every binary),
// and every return address is looked up in the symbol table of the
// executable, read from /proc/self/exe (on Linux; elsewhere, dladdr(3) only
// knows the exported symbols).  This costs nothing until a fatal error
// happens: a program runs the same code with backtraces on or off.  The
// table of names that the code generator writes with the directive turns the
// C names of the functions into their Idris names and the place of their
// definition.
//
// The frames that are not on the stack are not shown: those of the calls in
// tail position (jumps, or calls through a trampoline) and those of the
// functions that the C compiler inlined.
//
// A stack overflow hits the guard page under the stack of a green thread (or
// of the process); it is reported on an alternate signal stack of the OS
// thread.  What is done in a signal handler is meant to be async-signal-safe:
// no malloc, no stdio, only write(2) and reads of memory mapped at startup.
// It relies on the unwinder of libgcc (or of the system) being usable there,
// as glibc's backtrace(3) does, once it was called once (at startup), and on
// dladdr(3) for the frames of shared libraries, which takes a lock of the
// dynamic loader (a crash while that lock is held, in dlopen, say, would hang
// instead of being reported).
// ---------------------------------------------------------------------------

#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE // dladdr
#endif

#include "backtrace.h"
#include "threads.h"
#include "worker.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if IDRIS2_GREEN_THREADS && defined(__has_include)
#if __has_include(<unwind.h>) && __has_include(<dlfcn.h>)
#define BT_UNWIND 1
#endif
#endif
#ifndef BT_UNWIND
#define BT_UNWIND 0
#endif

#if BT_UNWIND && defined(__linux__) && __has_include(<link.h>) &&             \
    __has_include(<sys/auxv.h>)
#define BT_ELF 1
#else
#define BT_ELF 0
#endif

#if BT_UNWIND
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <unwind.h>
#endif

#if BT_ELF
#include <link.h>
#include <sys/auxv.h>
#if defined(__x86_64__) || defined(__aarch64__)
#include <ucontext.h>
#endif
#endif

static int bt_on = 0;
static int bt_default = 0;
static const Idris2_BacktraceName *bt_names = NULL;
static size_t bt_count = 0;

void idris2_backtraceNames(const Idris2_BacktraceName *names, size_t count) {
  bt_names = names;
  bt_count = count;
  bt_default = 1;
}

// ---------------------------------------------------------------------------
// Names

// Compare an entry of the table with the first `len` characters of `key`.
static int idris2_bt_keycmp(const char *entry, const char *key, size_t len) {
  int c = strncmp(entry, key, len);
  if (c != 0) {
    return c;
  }
  return entry[len] != '\0';
}

static const Idris2_BacktraceName *idris2_bt_find(const char *key, size_t len) {
  size_t lo = 0, hi = bt_count;
  while (lo < hi) {
    size_t mid = lo + (hi - lo) / 2;
    int c = idris2_bt_keycmp(bt_names[mid].cname, key, len);
    if (c == 0) {
      return &bt_names[mid];
    }
    if (c < 0) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return NULL;
}

static int idris2_bt_prefix(const char *s, size_t len, const char *p) {
  size_t n = strlen(p);
  return len >= n && strncmp(s, p, n) == 0;
}

// The C name of a function, without the prefix of the function that computes
// a constant or that borrows the arguments of a foreign function (see
// Compiler.RefC.RefC).  `*len` is its length, without the suffix that GCC adds
// to the parts and the copies of a function that it makes (`.cold`,
// `.isra.0`, `.constprop.0`, ...).
static const char *idris2_bt_base(const char *cname, size_t *len) {
  size_t n = strcspn(cname, ".");
  static const char *const prefixes[] = {"idris2_caf_", "idris2_borrow_"};
  for (size_t i = 0; i < sizeof(prefixes) / sizeof(prefixes[0]); i++) {
    if (idris2_bt_prefix(cname, n, prefixes[i])) {
      size_t k = strlen(prefixes[i]);
      cname += k;
      n -= k;
      break;
    }
  }
  *len = n;
  return cname;
}

// The entry of the table for a C name.
static const Idris2_BacktraceName *idris2_bt_lookup(const char *cname) {
  if (bt_count == 0) {
    return NULL;
  }
  size_t n;
  const char *base = idris2_bt_base(cname, &n);
  return idris2_bt_find(base, n);
}

// ---------------------------------------------------------------------------
// IDRIS2_REFC_DEMANGLE: the program as a filter that replaces the C names of
// its functions by their Idris names (for the output of perf, say).

static int idris2_bt_identChar(int c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
         (c >= '0' && c <= '9') || c == '_';
}

static void idris2_bt_demangleFilter(void) {
  if (bt_count == 0) {
    fprintf(stderr, "RefC: IDRIS2_REFC_DEMANGLE: this program has no table of "
                    "names; compile it with --directive refc-backtrace\n");
    exit(1);
  }
  size_t cap = 256, len = 0;
  char *tok = (char *)malloc(cap);
  if (!tok) {
    exit(1);
  }
  for (;;) {
    int c = getchar();
    if (c != EOF && idris2_bt_identChar(c)) {
      if (len + 1 >= cap) {
        cap *= 2;
        char *t = (char *)realloc(tok, cap);
        if (!t) {
          exit(1);
        }
        tok = t;
      }
      tok[len++] = (char)c;
      continue;
    }
    if (len > 0) {
      tok[len] = '\0';
      const Idris2_BacktraceName *e = idris2_bt_lookup(tok);
      fputs(e ? e->name : tok, stdout);
      len = 0;
    }
    if (c == EOF) {
      break;
    }
    putchar(c);
  }
  free(tok);
  fflush(stdout);
  exit(0);
}

#if BT_UNWIND

// ---------------------------------------------------------------------------
// Output (write(2), with a buffer of our own)

static char bt_out[1024];
static size_t bt_outLen = 0;

static void idris2_bt_flush(void) {
  size_t off = 0;
  while (off < bt_outLen) {
    ssize_t w = write(2, bt_out + off, bt_outLen - off);
    if (w < 0 && errno == EINTR) {
      continue;
    }
    if (w <= 0) {
      break;
    }
    off += (size_t)w;
  }
  bt_outLen = 0;
}

static void idris2_bt_putn(const char *s, size_t n) {
  for (size_t i = 0; i < n; i++) {
    if (bt_outLen == sizeof(bt_out)) {
      idris2_bt_flush();
    }
    bt_out[bt_outLen++] = s[i];
  }
}

static void idris2_bt_puts(const char *s) { idris2_bt_putn(s, strlen(s)); }

static void idris2_bt_putu(unsigned long long n) {
  char digits[24];
  int i = 0;
  do {
    digits[i++] = (char)('0' + n % 10);
    n /= 10;
  } while (n);
  while (i > 0) {
    idris2_bt_putn(&digits[--i], 1);
  }
}

// ---------------------------------------------------------------------------
// The symbols of the executable (from its ELF symbol table)

#if BT_ELF
static const ElfW(Sym) *elf_syms = NULL;
static size_t elf_nsyms = 0;
static const char *elf_strs = NULL;
static size_t elf_strsSize = 0;
static uintptr_t elf_bias = 0;

static const char *idris2_bt_elfLookup(uintptr_t pc) {
  for (size_t i = 0; i < elf_nsyms; i++) {
    const ElfW(Sym) *s = &elf_syms[i];
    int type = s->st_info & 0xf;
    if ((type != STT_FUNC && type != STT_GNU_IFUNC) ||
        s->st_shndx == SHN_UNDEF || s->st_name >= elf_strsSize) {
      continue;
    }
    uintptr_t start = (uintptr_t)s->st_value + elf_bias;
    uintptr_t size = s->st_size ? (uintptr_t)s->st_size : 1;
    if (pc >= start && pc - start < size) {
      return elf_strs + s->st_name;
    }
  }
  return NULL;
}

// Map the executable and find its symbol table, and where it is loaded.
static void idris2_bt_elfLoad(void) {
  int fd = open("/proc/self/exe", O_RDONLY | O_CLOEXEC);
  if (fd < 0) {
    return;
  }
  struct stat st;
  if (fstat(fd, &st) != 0 || (size_t)st.st_size < sizeof(ElfW(Ehdr))) {
    close(fd);
    return;
  }
  size_t size = (size_t)st.st_size;
  void *map = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
  close(fd);
  if (map == MAP_FAILED) {
    return;
  }
  const char *base = (const char *)map;
  const ElfW(Ehdr) *eh = (const ElfW(Ehdr) *)map;
  if (memcmp(eh->e_ident, ELFMAG, SELFMAG) != 0 ||
      eh->e_shentsize != sizeof(ElfW(Shdr)) ||
      eh->e_phentsize != sizeof(ElfW(Phdr)) || eh->e_shoff == 0 ||
      eh->e_shoff + (size_t)eh->e_shnum * sizeof(ElfW(Shdr)) > size ||
      eh->e_phoff + (size_t)eh->e_phnum * sizeof(ElfW(Phdr)) > size) {
    munmap(map, size);
    return;
  }
  // Where the program headers are in memory gives the load address.
  const ElfW(Phdr) *ph = (const ElfW(Phdr) *)(base + eh->e_phoff);
  uintptr_t phdrVaddr = 0;
  int havePhdr = 0;
  for (int i = 0; i < eh->e_phnum; i++) {
    if (ph[i].p_type == PT_PHDR) {
      phdrVaddr = (uintptr_t)ph[i].p_vaddr;
      havePhdr = 1;
      break;
    }
  }
  if (!havePhdr) {
    for (int i = 0; i < eh->e_phnum; i++) {
      if (ph[i].p_type == PT_LOAD && ph[i].p_offset == 0) {
        phdrVaddr = (uintptr_t)ph[i].p_vaddr + eh->e_phoff;
        havePhdr = 1;
        break;
      }
    }
  }
  uintptr_t atPhdr = (uintptr_t)getauxval(AT_PHDR);
  if (!havePhdr || atPhdr == 0) {
    munmap(map, size);
    return;
  }
  const ElfW(Shdr) *sh = (const ElfW(Shdr) *)(base + eh->e_shoff);
  // The full symbol table, or the dynamic one if the binary was stripped.
  for (int pass = 0; pass < 2 && !elf_syms; pass++) {
    unsigned want = pass == 0 ? SHT_SYMTAB : SHT_DYNSYM;
    for (int i = 0; i < eh->e_shnum; i++) {
      if (sh[i].sh_type != want || sh[i].sh_link >= eh->e_shnum) {
        continue;
      }
      const ElfW(Shdr) *strs = &sh[sh[i].sh_link];
      if (sh[i].sh_offset + sh[i].sh_size > size ||
          strs->sh_offset + strs->sh_size > size || strs->sh_size == 0 ||
          base[strs->sh_offset + strs->sh_size - 1] != '\0') {
        continue;
      }
      elf_syms = (const ElfW(Sym) *)(base + sh[i].sh_offset);
      elf_nsyms = sh[i].sh_size / sizeof(ElfW(Sym));
      elf_strs = base + strs->sh_offset;
      elf_strsSize = strs->sh_size;
      break;
    }
  }
  elf_bias = atPhdr - phdrVaddr;
  // Is it the right file (not one that took its place since)?
  const char *self = idris2_bt_elfLookup((uintptr_t)&idris2_backtracePrint);
  if (!self || strcmp(self, "idris2_backtracePrint") != 0) {
    elf_syms = NULL;
    elf_nsyms = 0;
    munmap(map, size);
  }
}
#endif

// What a return address is: the C name of its function and, if that is not
// in the executable, the file of the shared library that it is in.
typedef struct {
  const char *cname;
  const char *lib;
} Idris2_BtSym;

// (dladdr is only in libdl before glibc 2.34: a weak reference, which is
// NULL when the program is not linked with it)
#if defined(__linux__)
extern int dladdr(const void *, Dl_info *) __attribute__((weak));
#endif

static Idris2_BtSym idris2_bt_symbol(uintptr_t pc) {
  Idris2_BtSym r = {NULL, NULL};
#if BT_ELF
  r.cname = idris2_bt_elfLookup(pc);
  if (r.cname) {
    return r;
  }
#endif
#if defined(__linux__)
  if (!dladdr) {
    return r;
  }
#endif
  Dl_info info;
  if (dladdr((void *)pc, &info) != 0) {
    r.cname = info.dli_sname;
    if (info.dli_fname) {
      const char *slash = strrchr(info.dli_fname, '/');
      r.lib = slash ? slash + 1 : info.dli_fname;
    }
#if !BT_ELF
    // (the executable exports its functions on macOS)
    Dl_info me;
    if (dladdr((void *)&idris2_backtracePrint, &me) != 0 &&
        me.dli_fbase == info.dli_fbase) {
      r.lib = NULL;
    }
#endif
  }
  return r;
}

// ---------------------------------------------------------------------------
// Walking the stack

// The innermost frames, and the outermost ones of a deep stack (that of a
// stack overflow), and how many there are.
#define BT_HEAD 48
#define BT_TAIL 12
#define BT_LIMIT 5000000

static struct {
  uintptr_t head[BT_HEAD];
  uintptr_t tail[BT_TAIL];
  size_t n;
  int fromSignal; // skip the frames of the signal handler
  int started;
} walk;

static _Unwind_Reason_Code idris2_bt_frame(struct _Unwind_Context *ctx,
                                           void *arg) {
  (void)arg;
  int before = 0;
  uintptr_t ip = (uintptr_t)_Unwind_GetIPInfo(ctx, &before);
  if (ip == 0) {
    return _URC_END_OF_STACK;
  }
  if (!walk.started) {
    // The frame where the signal happened is the first one whose address
    // is that of an instruction, not a return address.
    if (walk.fromSignal && !before) {
      return _URC_NO_REASON;
    }
    walk.started = 1;
  }
  // (a return address may be the start of the next function, after a call
  // that does not return)
  if (!before) {
    ip -= 1;
  }
  if (walk.n < BT_HEAD) {
    walk.head[walk.n] = ip;
  }
  walk.tail[walk.n % BT_TAIL] = ip;
  walk.n++;
  return walk.n >= BT_LIMIT ? _URC_END_OF_STACK : _URC_NO_REASON;
}

static void idris2_bt_walk(int fromSignal) {
  walk.n = 0;
  walk.fromSignal = fromSignal;
  walk.started = 0;
  _Unwind_Backtrace(idris2_bt_frame, NULL);
  if (fromSignal && !walk.started) {
    // No frame of a signal: all of them, then.
    walk.n = 0;
    walk.fromSignal = 0;
    _Unwind_Backtrace(idris2_bt_frame, NULL);
  }
}

// ---------------------------------------------------------------------------
// Printing

// The functions where a stack begins: the frames below them are those of the
// runtime or of the C library.
static int idris2_bt_isBottom(const char *cname) {
  static const char *const bottoms[] = {"main_entry",     "thread_entry",
                                        "main",           "worker_main",
                                        "scheduler_loop", "__mainExpression_0"};
  size_t n = strcspn(cname, ".");
  for (size_t i = 0; i < sizeof(bottoms) / sizeof(bottoms[0]); i++) {
    if (strlen(bottoms[i]) == n && strncmp(cname, bottoms[i], n) == 0) {
      return 1;
    }
  }
  return 0;
}

// The frame being printed, which is not printed until the next one is known
// (consecutive frames of the same function make one line).
static struct {
  const char *name; // NULL when there is none
  size_t nameLen;
  const char *loc;
  const char *lib;
  int unknown;
  size_t count;
} line;

static void idris2_bt_endLine(void) {
  if (line.count == 0) {
    return;
  }
  idris2_bt_puts("  ");
  if (line.unknown) {
    idris2_bt_puts("??");
  } else {
    idris2_bt_putn(line.name, line.nameLen);
  }
  if (line.loc) {
    idris2_bt_puts(" (");
    idris2_bt_puts(line.loc);
    idris2_bt_puts(")");
  }
  if (line.lib) {
    idris2_bt_puts(" [");
    idris2_bt_puts(line.lib);
    idris2_bt_puts("]");
  }
  if (line.count > 1) {
    idris2_bt_puts(", ");
    idris2_bt_putu(line.count);
    idris2_bt_puts(" frames");
  }
  idris2_bt_puts("\n");
  line.count = 0;
}

static void idris2_bt_addLine(const char *name, size_t len, const char *loc,
                              const char *lib, int unknown) {
  if (line.count > 0 && line.unknown == unknown && line.nameLen == len &&
      (unknown || strncmp(line.name, name, len) == 0) && line.loc == loc &&
      line.lib == lib) {
    line.count++;
    return;
  }
  idris2_bt_endLine();
  line.name = name;
  line.nameLen = len;
  line.loc = loc;
  line.lib = lib;
  line.unknown = unknown;
  line.count = 1;
}

// Print the frame at `pc`; returns 0 at the bottom of the stack.
static int idris2_bt_printFrame(uintptr_t pc) {
  Idris2_BtSym sym = idris2_bt_symbol(pc);
  if (!sym.cname || !*sym.cname) {
    idris2_bt_addLine(NULL, 0, NULL, sym.lib, 1);
    return 1;
  }
  if (!sym.lib) {
    if (idris2_bt_isBottom(sym.cname)) {
      return 0;
    }
    const Idris2_BacktraceName *e = idris2_bt_lookup(sym.cname);
    if (e) {
      idris2_bt_addLine(e->name, strlen(e->name), e->loc, NULL, 0);
      return 1;
    }
    size_t n;
    const char *base = idris2_bt_base(sym.cname, &n);
    // (the functions of the runtime are left out)
    if (idris2_bt_prefix(base, n, "idris2_") ||
        idris2_bt_prefix(base, n, "Idris2_")) {
      return 1;
    }
    idris2_bt_addLine(base, n, NULL, NULL, 0);
    return 1;
  }
  idris2_bt_addLine(sym.cname, strlen(sym.cname), NULL, sym.lib, 0);
  return 1;
}

static void idris2_bt_print(void) {
  idris2_bt_puts("Backtrace of ");
  Idris2_Thread *thread = idris2_currentThread();
  int64_t id = thread ? idris2_threadId(thread) : -1;
  if (id == 0) {
    idris2_bt_puts("the main thread");
  } else if (id > 0) {
    idris2_bt_puts("thread ");
    idris2_bt_putu((unsigned long long)id);
  } else {
    idris2_bt_puts("the scheduler");
  }
  idris2_bt_puts(", innermost call first:\n");
  line.count = 0;
  size_t inHead = walk.n < BT_HEAD ? walk.n : BT_HEAD;
  int more = 1;
  for (size_t i = 0; i < inHead && more; i++) {
    more = idris2_bt_printFrame(walk.head[i]);
  }
  if (more && walk.n >= BT_LIMIT) {
    // (the outermost frames are not known)
    idris2_bt_endLine();
    idris2_bt_puts("  ... and more than ");
    idris2_bt_putu(BT_LIMIT - BT_HEAD);
    idris2_bt_puts(" more frames\n");
  } else if (more && walk.n > BT_HEAD) {
    idris2_bt_endLine();
    size_t first = walk.n - BT_TAIL > BT_HEAD ? walk.n - BT_TAIL : BT_HEAD;
    if (first > BT_HEAD) {
      idris2_bt_puts("  ... ");
      idris2_bt_putu(first - BT_HEAD);
      idris2_bt_puts(" more frames ...\n");
    }
    for (size_t i = first; i < walk.n && more; i++) {
      more = idris2_bt_printFrame(walk.tail[i % BT_TAIL]);
    }
  }
  idris2_bt_endLine();
  idris2_bt_flush();
}

// ---------------------------------------------------------------------------
// Fatal errors

// The OS thread that prints a backtrace: there is at most one, and a thread
// that crashes while another one reports waits for the program to end.
static _Thread_local char bt_me;
static void *bt_owner = NULL;

// 1 if this thread may report, 0 if it is reporting already (it crashed
// while reporting).
static int idris2_bt_claim(void) {
  void *expected = NULL;
  void *me = &bt_me;
  if (__atomic_compare_exchange_n(&bt_owner, &expected, me, 0, __ATOMIC_SEQ_CST,
                                  __ATOMIC_SEQ_CST)) {
    return 1;
  }
  if (expected == me) {
    return 0;
  }
  for (;;) {
    pause();
  }
}

void idris2_backtracePrint(void) {
  if (!bt_on || !idris2_bt_claim()) {
    return;
  }
  idris2_bt_walk(0);
  idris2_bt_print();
}

static const char *idris2_bt_signalName(int sig) {
  switch (sig) {
  case SIGSEGV:
    return "SIGSEGV";
  case SIGBUS:
    return "SIGBUS";
  case SIGFPE:
    return "SIGFPE";
  case SIGILL:
    return "SIGILL";
  case SIGABRT:
    return "SIGABRT";
  default:
    return "a signal";
  }
}

// Was the fault at `addr` that of a stack overflow?
static int idris2_bt_isOverflow(const void *addr, void *uc) {
  if (idris2_threadStackGuard(addr)) {
    return 1;
  }
#if BT_ELF && (defined(__x86_64__) || defined(__aarch64__))
  // Close to the stack pointer (on the stack of the process, say).
  ucontext_t *u = (ucontext_t *)uc;
#if defined(__x86_64__)
  uintptr_t sp = (uintptr_t)u->uc_mcontext.gregs[REG_RSP];
#else
  uintptr_t sp = (uintptr_t)u->uc_mcontext.sp;
#endif
  uintptr_t a = (uintptr_t)addr;
  return (a < sp ? sp - a : a - sp) < 65536;
#else
  (void)uc;
  return 0;
#endif
}

static void idris2_bt_signal(int sig, siginfo_t *info, void *uc) {
  int saved = errno;
  if (idris2_bt_claim()) {
    idris2_bt_puts("RefC: ");
    switch (sig) {
    case SIGSEGV:
      idris2_bt_puts(idris2_bt_isOverflow(info->si_addr, uc)
                         ? "stack overflow"
                         : "segmentation fault");
      break;
    case SIGBUS:
      idris2_bt_puts("bus error");
      break;
    case SIGFPE:
      idris2_bt_puts(info->si_code == FPE_INTDIV ? "integer division by zero"
                                                 : "arithmetic error");
      break;
    case SIGILL:
      idris2_bt_puts("illegal instruction");
      break;
    case SIGABRT:
      idris2_bt_puts("aborted");
      break;
    }
    idris2_bt_puts(" (");
    idris2_bt_puts(idris2_bt_signalName(sig));
    idris2_bt_puts(")\n");
    idris2_bt_walk(1);
    idris2_bt_print();
  }
  // Die of the signal, as without the handler: it is delivered again once
  // the handler returns (and a fault happens again).
  struct sigaction dfl;
  memset(&dfl, 0, sizeof(dfl));
  dfl.sa_handler = SIG_DFL;
  sigemptyset(&dfl.sa_mask);
  sigaction(sig, &dfl, NULL);
  raise(sig);
  errno = saved;
}

#define BT_ALTSTACK_SIZE (128 * 1024)

void idris2_backtraceThreadSetup(void) {
  if (!bt_on) {
    return;
  }
  void *stack = mmap(NULL, BT_ALTSTACK_SIZE, PROT_READ | PROT_WRITE,
                     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (stack == MAP_FAILED) {
    return;
  }
  stack_t ss;
  memset(&ss, 0, sizeof(ss));
  ss.ss_sp = stack;
  ss.ss_size = BT_ALTSTACK_SIZE;
  if (sigaltstack(&ss, NULL) != 0) {
    munmap(stack, BT_ALTSTACK_SIZE);
  }
}

static _Unwind_Reason_Code idris2_bt_stop(struct _Unwind_Context *ctx,
                                          void *arg) {
  (void)ctx;
  (void)arg;
  return _URC_END_OF_STACK;
}

static void idris2_bt_start(void) {
#if BT_ELF
  idris2_bt_elfLoad();
#endif
  // The unwinder and the dynamic loader may allocate memory the first time
  // they are used: not in a signal handler.
  _Unwind_Backtrace(idris2_bt_stop, NULL);
  (void)idris2_bt_symbol((uintptr_t)&idris2_bt_start);
  idris2_backtraceThreadSetup();
  struct sigaction sa;
  memset(&sa, 0, sizeof(sa));
  sa.sa_sigaction = idris2_bt_signal;
  sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
  sigemptyset(&sa.sa_mask);
  static const int signals[] = {SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGABRT};
  for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); i++) {
    sigaction(signals[i], &sa, NULL);
  }
}

#else /* !BT_UNWIND */

// No backtraces on this platform.
void idris2_backtracePrint(void) {}
void idris2_backtraceThreadSetup(void) {}
static void idris2_bt_start(void) { bt_on = 0; }

#endif

void idris2_backtraceSetup(void) {
  const char *demangle = getenv("IDRIS2_REFC_DEMANGLE");
  if (demangle && *demangle) {
    idris2_bt_demangleFilter();
  }
  const char *env = getenv("IDRIS2_REFC_BACKTRACE");
  bt_on = env && *env ? strcmp(env, "0") != 0 : bt_default;
  if (bt_on) {
    idris2_bt_start();
  }
}
