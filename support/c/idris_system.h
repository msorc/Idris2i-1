#pragma once

// Run `command` with the shell, wait for it, and return its exit status the
// way a shell reports it:
//  - its exit code when it exited, which is 127 when the shell could not be
//    run or could not find the command;
//  - 128 + the number of the signal when it was killed by a signal (so 143
//    for SIGTERM);
//  - -1 when no process could be created for it, or its status could not be
//    obtained (the C library's `system` returned -1).
// On Windows the C library's `system` already returns the exit code, which
// is returned unchanged.
int idris2i_1_system(const char *command);

// Start `sh -c command` without waiting for it, and return its process id,
// or -1 when it cannot be started (always on Windows).
int idris2i_1_spawnShell(const char *command);

// Wait for any child process to end, and return its process id, or -1 when
// there is none (always on Windows).  Its exit status is then given by
// idris2i_1_lastChildExitStatus (-1 when it did not exit normally).
int idris2i_1_waitAnyChild(void);
int idris2i_1_lastChildExitStatus(void);

// The processor time used by the process so far, in nanoseconds (0 on
// Windows), and its peak resident set size so far, in KiB (0 on Windows).
// They are cheap enough to be read often, by the compiler's profiler.
long long idris2i_1_processCPUTimeNs(void);
long long idris2i_1_peakRSSKiB(void);
