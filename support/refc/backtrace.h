#pragma once

// Backtraces of a program that dies of a fatal error (see backtrace.c).

#include <stddef.h>

// What the code generator knows of a function of the program: its C name,
// its Idris name, and where it is defined (NULL when it does not know).
// `--directive refc-backtrace` puts a table of them in the program, sorted
// by C name (in the order of strcmp).
typedef struct {
  const char *cname;
  const char *name;
  const char *loc;
} Idris2i_1_BacktraceName;

// Called by the main function of a program compiled with
// `--directive refc-backtrace`, before idris2i_1_threadSchedulerRun: the names
// of its functions, and backtraces on by default.
void idris2i_1_backtraceNames(const Idris2i_1_BacktraceName *names, size_t count);

// Called once at startup (by idris2i_1_threadSchedulerRun): reads
// IDRIS2I_1_REFC_BACKTRACE, and gets the backtraces ready when they are on.
// Then, when the variable IDRIS2I_1_REFC_DEMANGLE is set, the program copies its
// standard input to its standard output with the C names of its functions
// replaced by their Idris names, and exits.
void idris2i_1_backtraceSetup(void);

// Called by every worker (OS thread) that runs green threads when it starts:
// the alternate signal stack, on which a stack overflow is reported.
void idris2i_1_backtraceThreadSetup(void);

// Prints the backtrace of the current thread on stderr, when backtraces are
// on: after the message of a fatal error, before the program exits.
void idris2i_1_backtracePrint(void);

// The backtrace of the current thread as text (allocated with malloc), as
// idris2i_1_backtracePrint would print it, down to the innermost crash
// boundary (see crash.c); NULL when backtraces are off.
char *idris2i_1_backtraceCapture(void);

// What the functions of a program compiled with `--directive refc-backtrace`
// are declared with: a function that is inlined has no frame of its own.
#if defined(__GNUC__) || defined(__clang__)
#define IDRIS2I_1_BT_NOINLINE __attribute__((noinline))
#else
#define IDRIS2I_1_BT_NOINLINE
#endif

// Put after a call that would be the last thing that a function does, so
// that the C compiler does not make it a jump: the frame of the function
// stays on the stack during the call, for the backtraces.
#if defined(__GNUC__) || defined(__clang__)
#define IDRIS2I_1_BT_KEEP_FRAME() __asm__ volatile("" ::: "memory")
#else
#define IDRIS2I_1_BT_KEEP_FRAME()
#endif
