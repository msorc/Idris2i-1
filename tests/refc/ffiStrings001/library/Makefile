all: libffistrings.so

ffistrings.o: ffistrings.c ffistrings.h
	$(CC) -c -fPIC $< -o $@

libffistrings.so: ffistrings.o
	$(CC) $< -shared -o $@

clean:
	rm -f ffistrings.o libffistrings.so
