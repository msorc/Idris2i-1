/* Run a command and report its peak resident set size and its wall time.
 *
 *   maxrss OUT -- COMMAND [ARGS...]
 *
 * appends "MAXRSS_KB,ELAPSED_S" to the file OUT.  The command is started
 * with vfork: on Linux, the peak RSS of a process survives exec, so a child
 * forked from a large process would report at least the size of its parent.
 * Used by refc-perf.sh. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv) {
  if (argc < 4 || strcmp(argv[2], "--") != 0) {
    fprintf(stderr, "usage: %s OUT -- COMMAND [ARGS...]\n", argv[0]);
    return 2;
  }
  struct timespec t0, t1;
  clock_gettime(CLOCK_MONOTONIC, &t0);
  pid_t pid = vfork();
  if (pid < 0) {
    perror("vfork");
    return 2;
  }
  if (pid == 0) {
    execvp(argv[3], argv + 3);
    _exit(127);
  }
  int status = 0;
  struct rusage ru;
  if (wait4(pid, &status, 0, &ru) < 0) {
    perror("wait4");
    return 2;
  }
  clock_gettime(CLOCK_MONOTONIC, &t1);
  double elapsed = (double)(t1.tv_sec - t0.tv_sec) +
                   (double)(t1.tv_nsec - t0.tv_nsec) / 1e9;
  FILE *out = fopen(argv[1], "a");
  if (!out) {
    perror(argv[1]);
    return 2;
  }
  fprintf(out, "%ld,%.3f\n", ru.ru_maxrss, elapsed);
  fclose(out);
  if (WIFEXITED(status))
    return WEXITSTATUS(status);
  return 128 + (WIFSIGNALED(status) ? WTERMSIG(status) : 0);
}
