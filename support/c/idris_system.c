#include <stdlib.h>

#ifndef _WIN32
#include <errno.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#endif

#include "idris_system.h"

int idris2i_1_system(const char *command) {
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

int idris2i_1_spawnShell(const char *command) {
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

static int idris2i_1_lastChildStatus = -1;

int idris2i_1_waitAnyChild(void) {
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
  idris2i_1_lastChildStatus = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
  return (int)pid;
#endif
}

int idris2i_1_lastChildExitStatus(void) { return idris2i_1_lastChildStatus; }

long long idris2i_1_processCPUTimeNs(void) {
#ifdef _WIN32
  return 0;
#else
  struct timespec ts;
  if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts) != 0)
    return 0;
  return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
#endif
}

long long idris2i_1_peakRSSKiB(void) {
#ifdef _WIN32
  return 0;
#else
  struct rusage ru;
  if (getrusage(RUSAGE_SELF, &ru) != 0)
    return 0;
#ifdef __APPLE__
  return (long long)ru.ru_maxrss / 1024; // bytes on macOS
#else
  return (long long)ru.ru_maxrss;
#endif
#endif
}
