#pragma once

// Return non-zero if the pointer is null
int idris2i_1_isNull(void *);
// Returns a NULL
void *idris2i_1_getNull();
// Convert a Ptr String intro a String, assuming the string has been checked
// to be non-null
char *idris2i_1_getString(void *p);
int idris2i_1_getErrno();
char *idris2i_1_strerror(int errnum);

char *idris2i_1_getStr();
void idris2i_1_putStr(char *f);

void idris2i_1_sleep(int sec);
void idris2i_1_usleep(int usec);
int idris2i_1_time();

int idris2i_1_getArgCount();
void idris2i_1_setArgs(int argc, char *argv[]);
char *idris2i_1_getArg(int n);
char *idris2i_1_getEnvPair(int i);
int idris2i_1_setenv(const char *name, const char *value, int overwrite);
int idris2i_1_unsetenv(const char *name);

// Raw mode of the terminal on stdin (no echo, no line buffering)
int idris2i_1_enableRawMode();
void idris2i_1_resetRawMode();

int idris2i_1_getPID();

long idris2i_1_getNProcessors();
