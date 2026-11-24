#pragma once

char *idris2i_1_currentDirectory();
int idris2i_1_changeDir(char *dir);
int idris2i_1_createDir(char *dir);
void *idris2i_1_openDir(char *dir);
void idris2i_1_closeDir(void *d);
int idris2i_1_removeDir(char *path);
char *idris2i_1_nextDirEntry(void *d);
