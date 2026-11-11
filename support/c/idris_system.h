#pragma once

int idris2_system(const char *command);

// Start `sh -c command` without waiting for it, and return its process id,
// or -1 when it cannot be started (always on Windows).
int idris2_spawnShell(const char *command);

// Wait for any child process to end, and return its process id, or -1 when
// there is none (always on Windows).  Its exit status is then given by
// idris2_lastChildExitStatus (-1 when it did not exit normally).
int idris2_waitAnyChild(void);
int idris2_lastChildExitStatus(void);
