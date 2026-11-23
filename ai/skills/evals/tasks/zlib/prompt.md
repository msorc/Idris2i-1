I want to call zlib from Idris 2 (zlib is installed on this machine: `zlib.h`, `-lz`).

Write a program `zcheck` that takes one argument, a string, and prints three lines:

1. the CRC-32 of the string's bytes (UTF-8), as 8 lower-case hexadecimal digits,
   computed with zlib's `crc32`
2. `compressed N`, where N is the number of bytes zlib's `compress` produces for those
   bytes
3. `roundtrip ok` if `uncompress` on that output gives the original bytes back,
   otherwise `roundtrip FAILED`

The work must be done by zlib through the FFI, not reimplemented in Idris. Put the
build commands in `build.sh`, so that `sh build.sh` produces `build/exec/zcheck`. Use
the compiler's default back end.
