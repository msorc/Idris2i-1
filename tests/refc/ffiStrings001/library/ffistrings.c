#include "ffistrings.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const char *dayName(int day) {
  static const char *names[] = {"Monday", "Tuesday", "Wednesday", "Thursday",
                                "Friday", "Saturday", "Sunday"};
  return names[((day % 7) + 7) % 7];
}

char *greeting(const char *name) {
  size_t size = strlen(name) + 9;
  char *str = malloc(size);
  if (str != NULL)
    snprintf(str, size, "Hello, %s!", name);
  return str;
}

void freeGreeting(char *str) { free(str); }

static char *title = NULL;

void setTitle(const char *newTitle) {
  free(title);
  // The argument is only valid during the call: keep a copy.
  title = strdup(newTitle);
}

const char *getTitle(void) { return title == NULL ? "" : title; }

void clearTitle(void) {
  free(title);
  title = NULL;
}
