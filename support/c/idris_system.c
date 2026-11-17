#include <stdlib.h>

#ifndef _WIN32
#include <errno.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

#include "idris_system.h"

int idris2_system(const char *command) {
  int status = system(command);
#ifdef _WIN32
  return status;
#else
  if (status == -1)
    return -1; // no child process, or no status for it
  if (WIFEXITED(status))
    return WEXITSTATUS(status);
  if (WIFSIGNALED(status))
    return 128 + WTERMSIG(status);
  return -1; // `system` waits for termination, so this is not expected
#endif
}

int idris2_spawnShell(const char *command) {
#ifdef _WIN32
  (void)command;
  return -1;
#else
  pid_t pid = fork();
  if (pid == 0) {
    execl("/bin/sh", "sh", "-c", command, (char *)NULL);
    _exit(127);
  }
  return pid < 0 ? -1 : (int)pid;
#endif
}

static int idris2_lastChildStatus = -1;

int idris2_waitAnyChild(void) {
#ifdef _WIN32
  return -1;
#else
  int status;
  pid_t pid;
  do {
    pid = waitpid(-1, &status, 0);
  } while (pid == -1 && errno == EINTR);
  if (pid == -1)
    return -1;
  idris2_lastChildStatus = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
  return (int)pid;
#endif
}

int idris2_lastChildExitStatus(void) { return idris2_lastChildStatus; }
