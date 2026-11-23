#ifndef GEOM_H
#define GEOM_H

/* A polyline: a growing list of points. */
typedef struct polyline polyline;

typedef struct {
    double x;
    double y;
} point;

/* A new, empty polyline; NULL when out of memory. Free it with polyline_free. */
polyline *polyline_new(void);
void polyline_free(polyline *line);

/* Appends a point. Returns the new number of points, or -1 when out of memory. */
int polyline_add(polyline *line, double x, double y);

int polyline_count(const polyline *line);

/* Stores point number `index` in *out and returns 1; returns 0 when there is no
   such point, and leaves *out alone. */
int polyline_get(const polyline *line, int index, point *out);

/* Sum of the lengths of the segments. */
double polyline_length(const polyline *line);

/* Calls visit(index, x, y) for each point, in order. */
void polyline_each(const polyline *line, void (*visit)(int index, double x, double y));

/* A description such as "polyline(3 points, length 7.00)". The caller owns the
   returned string and must release it with free(). NULL when out of memory. */
char *polyline_describe(const polyline *line);

#endif
