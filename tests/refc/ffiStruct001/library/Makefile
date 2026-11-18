all: libstructs.so

structs.o: structs.c structs.h
	$(CC) -c -fPIC $< -o $@

libstructs.so: structs.o
	$(CC) $< -shared -o $@

clean:
	rm -f structs.o libstructs.so
