#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Each function copies its argument, calls back into Idris, which makes the
// Scheme collector run, and then says whether the argument is unchanged.

int checkString(char *s, void (*cb)(void)) {
    size_t n = strlen(s);
    char *copy = malloc(n + 1);
    memcpy(copy, s, n + 1);
    cb();
    int same = strcmp(copy, s) == 0;
    free(copy);
    return same;
}

int checkBuffer(uint8_t *b, int n, void (*cb)(void)) {
    uint8_t *copy = malloc(n);
    memcpy(copy, b, n);
    cb();
    int same = memcmp(copy, b, n) == 0;
    free(copy);
    return same;
}
