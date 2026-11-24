#pragma once

#include <stdint.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/types.h>

#ifdef _WIN32
#include <io.h>
#include <processthreadsapi.h>
#endif

FILE *idris2i_1_openFile(char *name, char *mode);
void idris2i_1_closeFile(FILE *f);

int idris2i_1_fileError(FILE *f);

// Turn errno into an integer understandable by System.File
int idris2i_1_fileErrno();

int idris2i_1_chmod(const char *path, mode_t mode);
int idris2i_1_removeFile(const char *filename);
int idris2i_1_fileSize(FILE *h);

int idris2i_1_fpoll(FILE *f);

void *idris2i_1_popen(const char *cmd, const char *mode);
int idris2i_1_pclose(void *stream);

// Seek through the next newline without
// saving anything along the way
int idris2i_1_seekLine(FILE *f);

// Treat as a Ptr String (might be NULL)
char *idris2i_1_readLine(FILE *f);
char *idris2i_1_readChars(int num, FILE *f);
size_t idris2i_1_readBufferData(FILE *h, char *buffer, size_t loc, size_t max);

int idris2i_1_writeLine(FILE *f, char *str);
size_t idris2i_1_writeBufferData(FILE *h, const char *buffer, size_t loc,
                              size_t len);

int idris2i_1_eof(FILE *f);

struct filetime;

struct filetime *idris2i_1_fileTime(FILE *f);
int idris2i_1_fileModifiedTime(FILE *f);

int idris2i_1_filetimeAccessTimeSec(struct filetime *f);
int idris2i_1_filetimeAccessTimeNsec(struct filetime *f);
int idris2i_1_filetimeModifiedTimeSec(struct filetime *f);
int idris2i_1_filetimeModifiedTimeNsec(struct filetime *f);
int idris2i_1_filetimeStatusTimeSec(struct filetime *f);
int idris2i_1_filetimeStatusTimeNsec(struct filetime *f);

int idris2i_1_fileIsTTY(FILE *f);

FILE *idris2i_1_stdin();
FILE *idris2i_1_stdout();
FILE *idris2i_1_stderr();

struct child_process;

struct child_process *idris2i_1_popen2(char *cmd);

int idris2i_1_popen2ChildPid(struct child_process *ptr);
void *idris2i_1_popen2ChildHandler(struct child_process *ptr);
FILE *idris2i_1_popen2FileIn(struct child_process *ptr);
FILE *idris2i_1_popen2FileOut(struct child_process *ptr);

int idris2i_1_popen2WaitByHandler(void *hProcess);
int idris2i_1_popen2WaitByPid(pid_t pid);
