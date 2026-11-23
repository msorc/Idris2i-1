#include "geom.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

struct polyline {
    point *points;
    int count;
    int capacity;
};

polyline *polyline_new(void) {
    polyline *line = malloc(sizeof *line);
    if (line == NULL) return NULL;
    line->points = NULL;
    line->count = 0;
    line->capacity = 0;
    return line;
}

void polyline_free(polyline *line) {
    if (line == NULL) return;
    free(line->points);
    free(line);
}

int polyline_add(polyline *line, double x, double y) {
    if (line->count == line->capacity) {
        int capacity = line->capacity == 0 ? 4 : line->capacity * 2;
        point *points = realloc(line->points, (size_t)capacity * sizeof *points);
        if (points == NULL) return -1;
        line->points = points;
        line->capacity = capacity;
    }
    line->points[line->count].x = x;
    line->points[line->count].y = y;
    return ++line->count;
}

int polyline_count(const polyline *line) {
    return line->count;
}

int polyline_get(const polyline *line, int index, point *out) {
    if (index < 0 || index >= line->count) return 0;
    *out = line->points[index];
    return 1;
}

double polyline_length(const polyline *line) {
    double total = 0;
    for (int i = 1; i < line->count; i++) {
        double dx = line->points[i].x - line->points[i - 1].x;
        double dy = line->points[i].y - line->points[i - 1].y;
        total += sqrt(dx * dx + dy * dy);
    }
    return total;
}

void polyline_each(const polyline *line, void (*visit)(int index, double x, double y)) {
    for (int i = 0; i < line->count; i++) {
        visit(i, line->points[i].x, line->points[i].y);
    }
}

char *polyline_describe(const polyline *line) {
    char *text = malloc(64);
    if (text == NULL) return NULL;
    snprintf(text, 64, "polyline(%d points, length %.2f)", line->count, polyline_length(line));
    return text;
}
