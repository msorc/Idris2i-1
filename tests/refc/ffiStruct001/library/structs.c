#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include "structs.h"

point *mkPoint(int x, int y) {
    point *pt = malloc(sizeof(point));
    pt->x = x;
    pt->y = y;
    return pt;
}

void freePoint(point *pt) { free(pt); }

int sumPoint(point *pt) { return pt->x + pt->y; }

point *asPoint(void *p) { return p; }

int sizeofPoint(void) { return sizeof(point); }

namedpoint *mkNamedPoint(char *str, point *p) {
    namedpoint *np = malloc(sizeof(namedpoint));
    /* (the string of the caller lives only as long as the call) */
    np->name = strdup(str);
    np->pt = p;
    return np;
}

void freeNamedPoint(namedpoint *np) {
    free(np->name);
    free(np);
}

char *getString(void *p) { return (char *)p; }

fields *mkFields(void) {
    fields *f = malloc(sizeof(fields));
    f->c = 'a';
    f->i = -1;
    f->i8 = -8;
    f->i16 = -16;
    f->i32 = -32;
    f->i64 = -64;
    f->b8 = 8;
    f->b16 = 16;
    f->b32 = 32;
    f->b64 = 64;
    f->d = 0.5;
    f->p = NULL;
    f->last = 'z';
    return f;
}

void freeFields(fields *f) { free(f); }

void showFields(fields *f) {
    printf("C: %c %d %d %d %" PRId32 " %" PRId64 " %u %u %" PRIu32 " %" PRIu64
           " %g %s %c\n",
           f->c, f->i, f->i8, f->i16, f->i32, f->i64, f->b8, f->b16, f->b32,
           f->b64, f->d, f->p == NULL ? "null" : "not null", f->last);
    fflush(stdout);
}
