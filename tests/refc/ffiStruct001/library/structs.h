#pragma once
#include <stdint.h>

/* The names of the structs are those that the Idris program uses: the
   generated C defines structs of its own for them, and includes this file. */

typedef struct point {
    int x;
    int y;
} point;

typedef struct namedpoint {
    char *name;
    point *pt;
} namedpoint;

/* A field of each type: the layout has padding between the fields. */
typedef struct fields {
    char c;
    int i;
    int8_t i8;
    int16_t i16;
    int32_t i32;
    int64_t i64;
    uint8_t b8;
    uint16_t b16;
    uint32_t b32;
    uint64_t b64;
    double d;
    void *p;
    char last;
} fields;

point *mkPoint(int x, int y);
void freePoint(point *pt);
int sumPoint(point *pt);
point *asPoint(void *p);
int sizeofPoint(void);

namedpoint *mkNamedPoint(char *str, point *p);
void freeNamedPoint(namedpoint *np);
char *getString(void *p);

fields *mkFields(void);
void freeFields(fields *f);
void showFields(fields *f);
