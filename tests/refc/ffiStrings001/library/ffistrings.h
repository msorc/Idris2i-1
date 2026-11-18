#pragma once

// A string that the library keeps: the caller must not free it.
const char *dayName(int day);

// A new string from malloc: the caller frees it, with freeGreeting.
char *greeting(const char *name);
void freeGreeting(char *str);

// The library keeps a copy of the string, not the pointer that it is given.
void setTitle(const char *title);
const char *getTitle(void);
void clearTitle(void);
