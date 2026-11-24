`geom.h` and `geom.c` are a small C library that I cannot change. Write Idris2i-1
bindings for it in `Geom.idr` and a program `Main.idr` that uses every function of the
library through the bindings.

The program takes numbers on the command line, two per point (`x1 y1 x2 y2 ...`), adds
the points to a polyline and prints:

1. `count N`
2. for each point, through `polyline_each`: `point I: X Y`
3. `last: X Y`, read back with `polyline_get` (or `last: none` for an empty polyline)
4. `get 99: none`, from asking `polyline_get` for point 99
5. `length L`, from `polyline_length`
6. the text from `polyline_describe`

Print a `Double` with Idris2i-1's `show`. For `./build/exec/geom 0 0 3 4 3 10` the output is:

```
count 3
point 0: 0.0 0.0
point 1: 3.0 4.0
point 2: 3.0 10.0
last: 3.0 10.0
get 99: none
length 11.0
polyline(3 points, length 11.00)
```

Every allocation made by the library must be released before the program exits. Put
the build commands in `build.sh`, so that `sh build.sh` produces `build/exec/geom`, with
the compiler's default back end.
