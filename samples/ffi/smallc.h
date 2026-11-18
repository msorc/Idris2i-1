#pragma once

// The struct and the functions of `smallc.c` that `Struct.idr` uses. The RefC code generator
// includes this file in the C of the program (see the `%foreign` declarations of `Struct.idr`).

typedef struct {
    int x;
    int y;
} point;

point* mkPoint(int x, int y);
void freePoint(point* pt);
