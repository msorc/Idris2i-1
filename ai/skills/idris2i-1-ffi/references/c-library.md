# A complete binding: SQLite, with glue C

<!-- idris
import Data.Buffer
import Data.Maybe
import System.FFI
-->

This file is a program. It binds the parts of SQLite 3 that a real binding needs and
shows each technique once. It was built with RefC (the default back end) on Linux
against SQLite 3.53 and run, and Valgrind found no errors and no leaks. The output is at
the end.

Contents

1. Layout and build commands
2. The glue C
3. Linking, and the specifier helpers
4. A cell for out-parameters (a one-field `Struct`)
5. The foreign functions
6. Handles, errors and a finaliser
7. Statements, strings in and out, blobs in a `Buffer`
8. A callback into Idris2i-1 (`sqlite3_exec`)
9. A struct of libc: `struct tm`
10. The program and its output
11. With Chez

## 1. Layout and build commands

```text
notes/
  Notes.idr            the Idris below (or this file itself, Notes.md)
  c/sqlite_glue.c      the glue C below
  c/sqlite_glue.h
  lib/                 made by the build: the header and the object for RefC
```

```sh
mkdir -p lib
cp c/sqlite_glue.h lib/
cc -c -fPIC -I"$(idris2i-1 --libdir)/support/refc" -o lib/sqlite_glue.o c/sqlite_glue.c
idris2i-1 -o notes Notes.idr
./build/exec/notes
```

No environment variables are needed: `./lib` is a directory where RefC looks both for
the archives of `refc-archive` and for headers, and `pkg-config` gives the flags of
SQLite. The glue includes `runtime.h` (for the callback), whose directory is
`$(idris2i-1 --libdir)/support/refc`.

## 2. The glue C

Glue is needed for what Idris2i-1 cannot express: a C macro (`SQLITE_TRANSIENT`), a
`const` result (RefC compiles with `-Werror`, and `const void *` does not convert to the
`void *` of an `AnyPtr`), and a C function pointer (RefC passes an Idris2i-1 closure).

```c
/* c/sqlite_glue.h */
#ifndef SQLITE_GLUE_H
#define SQLITE_GLUE_H
#include <sqlite3.h>
#include <runtime.h>

int glue_bind_text(sqlite3_stmt *stmt, int i, const char *text);
int glue_bind_blob(sqlite3_stmt *stmt, int i, const void *bytes, int n);
void *glue_column_text(sqlite3_stmt *stmt, int i);
void *glue_column_blob(sqlite3_stmt *stmt, int i);
int glue_exec(sqlite3 *db, const char *sql, Idris2i_1_Closure *row, char **err);
#endif
```

```c
/* c/sqlite_glue.c */
#include "sqlite_glue.h"

/* SQLITE_TRANSIENT makes SQLite copy the text: the char * of an Idris String
   is only valid until the call returns. */
int glue_bind_text(sqlite3_stmt *stmt, int i, const char *text) {
  return sqlite3_bind_text(stmt, i, text, -1, SQLITE_TRANSIENT);
}

int glue_bind_blob(sqlite3_stmt *stmt, int i, const void *bytes, int n) {
  return sqlite3_bind_blob(stmt, i, bytes, n, SQLITE_TRANSIENT);
}

/* Drop the const, which -Werror would refuse to drop silently. */
void *glue_column_text(sqlite3_stmt *stmt, int i) {
  return (void *)sqlite3_column_text(stmt, i);
}

void *glue_column_blob(sqlite3_stmt *stmt, int i) {
  return (void *)sqlite3_column_blob(stmt, i);
}

/* The trampoline: SQLite calls it with the user data, which is the Idris
   closure, of type String -> String -> PrimIO Int32.  Applying a closure
   consumes a reference to it and to each argument, so take a new reference
   to the closure for each call; the result is a new reference, released. */
static int glue_row(void *ud, int n, char **vals, char **names) {
  for (int i = 0; i < n; i++) {
    Idris2i_1_Value *clos = idris2i_1_newReference((Idris2i_1_Value *)ud);
    Idris2i_1_Value *name = (Idris2i_1_Value *)idris2i_1_mkString(names[i]);
    Idris2i_1_Value *val =
        (Idris2i_1_Value *)idris2i_1_mkString(vals[i] ? vals[i] : "NULL");
    Idris2i_1_Value *act = idris2i_1_apply_closure2(clos, name, val);
    Idris2i_1_Value *res = idris2i_1_apply_closure(act, NULL); /* run the PrimIO */
    int32_t stop = idris2i_1_vp_to_Int32(res);
    idris2i_1_removeReference(res);
    if (stop != 0) return stop;
  }
  return 0;
}

/* The closure is borrowed for the call, which is all that sqlite3_exec
   needs.  A library that keeps a callback for later must keep a reference
   (idris2i_1_newReference) until it is done with it. */
int glue_exec(sqlite3 *db, const char *sql, Idris2i_1_Closure *row, char **err) {
  return sqlite3_exec(db, sql, glue_row, row, err);
}
```

A `PrimIO` callback is a closure that takes its arguments and then the world:
`idris2i_1_apply_closure(act, NULL)` runs it. A pure callback (`Int -> Int`) is applied to
its arguments only. `idris2i_1_mkInt64`, `idris2i_1_vp_to_Int64`, `idris2i_1_mkString` and the
others are in the headers of `support/refc`.

## 3. Linking, and the specifier helpers

The module that binds the library says what to link (this fork), so a program that
imports it needs no flags. The library part of a specifier is for Chez; RefC uses the
header.

```idris
%cg refc refc-pkg-config=sqlite3
%cg refc refc-archive=sqlite_glue.o

sqlite : String -> String
sqlite fn = "C:" ++ fn ++ ",libsqlite3,sqlite3.h"

glue : String -> String
glue fn = "C:" ++ fn ++ ",libsqlite_glue,sqlite_glue.h"
```

`%foreign sqlite "sqlite3_open"` below is one specifier, the application
`sqlite "sqlite3_open"`.

## 4. A cell for out-parameters

`sqlite3_open(const char *, sqlite3 **)` writes the handle through a pointer. Idris2i-1 has
no `&` and no `peek`, but a `Struct` is a pointer to C memory that `getField` reads: a
struct of one pointer field is a cell that C can write. `calloc`, bound with the struct
as its result type, allocates it.

```idris
Cell : Type
Cell = Struct "ptr_cell" [("p", AnyPtr)]

%foreign "C:calloc,libc,stdlib.h"
prim__newCell : Int -> Int -> PrimIO Cell

%foreign "C:free,libc,stdlib.h"
prim__freeCell : Cell -> PrimIO ()
```

`getField` is pure, so nothing orders it before `prim__freeCell`: free the cell only
after the last use of what was read from it, as the functions below do.

## 5. The foreign functions

Pure only for `sqlite3_libversion`, a constant string. The others read or change the
state of the database, so they are `PrimIO`. C `int` is `Int32`.

```idris
%foreign sqlite "sqlite3_libversion"
libVersion : String

%foreign sqlite "sqlite3_open"
prim__open : String -> Cell -> PrimIO Int32

%foreign sqlite "sqlite3_close_v2"
prim__close : AnyPtr -> PrimIO Int32

%foreign sqlite "sqlite3_errmsg"
prim__errmsg : GCAnyPtr -> PrimIO String

%foreign sqlite "sqlite3_free"
prim__sqliteFree : AnyPtr -> PrimIO ()

%foreign sqlite "sqlite3_prepare_v2"
prim__prepare : GCAnyPtr -> String -> Int32 -> Cell -> AnyPtr -> PrimIO Int32

%foreign sqlite "sqlite3_step"
prim__step : AnyPtr -> PrimIO Int32

%foreign sqlite "sqlite3_finalize"
prim__finalize : AnyPtr -> PrimIO Int32

%foreign sqlite "sqlite3_column_int64"
prim__columnInt : AnyPtr -> Int32 -> PrimIO Int64

%foreign glue "glue_column_text"
prim__columnText : AnyPtr -> Int32 -> PrimIO (Ptr String)

%foreign glue "glue_column_blob"
prim__columnBlob : AnyPtr -> Int32 -> PrimIO AnyPtr

%foreign sqlite "sqlite3_column_bytes"
prim__columnBytes : AnyPtr -> Int32 -> PrimIO Int32

%foreign glue "glue_bind_text"
prim__bindText : AnyPtr -> Int32 -> String -> PrimIO Int32

%foreign glue "glue_bind_blob"
prim__bindBlob : AnyPtr -> Int32 -> Buffer -> Int32 -> PrimIO Int32

%foreign glue "glue_exec"
prim__exec : GCAnyPtr -> String -> (String -> String -> PrimIO Int32) -> Cell ->
             PrimIO Int32

%foreign "C:idris2i_1_getString,libidris2i_1_support,idris_support.h"
prim__copyString : Ptr String -> PrimIO String

%foreign "C:memcpy,libc,string.h"
prim__memcpy : Buffer -> AnyPtr -> Int -> PrimIO AnyPtr
```

`Buffer` is passed as a pointer to its bytes, so `memcpy` can fill one from a pointer
of the library.

## 6. Handles, errors and a finaliser

The database handle is an opaque pointer, kept in a `GCAnyPtr` whose finaliser closes
it. Errors are values: the result code and SQLite's message, which the library keeps
(so `String` is the right result type of `sqlite3_errmsg`).

```idris
record SqlError where
  constructor MkSqlError
  code : Int32
  message : String

Show SqlError where
  show e = "error " ++ show e.code ++ ": " ++ e.message

record Db where
  constructor MkDb
  handle : GCAnyPtr

sqliteOk, sqliteRow, sqliteDone : Int32
sqliteOk = 0
sqliteRow = 100
sqliteDone = 101

-- sqlite3_open gives a handle even when it fails; it holds the message and
-- must be closed too, so it gets the finaliser either way.
openDb : HasIO io => String -> io (Either SqlError Db)
openDb path = do
  cell <- primIO $ prim__newCell 1 8
  rc <- primIO $ prim__open path cell
  h <- liftIO $ onCollectAny (getField cell "p") $ \p => do
         putStrLn "(closing the database)"
         ignore $ primIO $ prim__close p
  primIO $ prim__freeCell cell
  if rc == sqliteOk
     then pure (Right (MkDb h))
     else pure (Left (MkSqlError rc !(primIO $ prim__errmsg h)))

lastError : HasIO io => Db -> Int32 -> io SqlError
lastError db rc = pure (MkSqlError rc !(primIO $ prim__errmsg db.handle))
```

`sqlite3_close_v2`, not `sqlite3_close`: a finaliser runs whenever the run time decides
(with RefC when the last reference goes, which the output below shows; with Chez at a
collection or at exit), possibly before statements are finalised, and `close_v2` waits
for them instead of failing with `SQLITE_BUSY`.

## 7. Statements, strings in and out, blobs

A statement is finalised in a bracket rather than by a finaliser, so that it surely goes
before the database.

```idris
Stmt : Type
Stmt = AnyPtr

withStmt : HasIO io => Db -> String -> (Stmt -> io (Either SqlError a)) ->
           io (Either SqlError a)
withStmt db sql act = do
  cell <- primIO $ prim__newCell 1 8
  rc <- primIO $ prim__prepare db.handle sql (-1) cell prim__getNullAnyPtr
  let stmt : Stmt = getField cell "p"
  r <- if rc /= sqliteOk
          then Left <$> lastError db rc
          else do r <- act stmt
                  _ <- primIO $ prim__finalize stmt
                  pure r
  primIO $ prim__freeCell cell
  pure r

check : HasIO io => Db -> Int32 -> io (Either SqlError ())
check db rc = if rc == sqliteOk then pure (Right ()) else Left <$> lastError db rc
```

The text of a column belongs to SQLite, is valid until the next step, and is `NULL` for
SQL `NULL`: a `Ptr String`, tested, then copied by an IO action at once. A blob is
copied into a `Buffer`, which Idris2i-1 owns.

```idris
columnText : HasIO io => Stmt -> Int32 -> io (Maybe String)
columnText stmt i = do
  p <- primIO $ prim__columnText stmt i
  if prim__nullPtr p /= 0
     then pure Nothing
     else Just <$> primIO (prim__copyString p)

columnBlob : HasIO io => Stmt -> Int32 -> io (Maybe Buffer)
columnBlob stmt i = do
  p <- primIO $ prim__columnBlob stmt i
  n <- primIO $ prim__columnBytes stmt i
  Just buf <- newBuffer (cast n) | Nothing => pure Nothing
  when (n > 0) $ ignore $ primIO $ prim__memcpy buf p (cast n)
  pure (Just buf)

insertNote : HasIO io => Db -> String -> Buffer -> io (Either SqlError ())
insertNote db body bytes =
  withStmt db "INSERT INTO notes(body, data) VALUES (?1, ?2)" $ \stmt => do
    n <- rawSize bytes
    Right () <- check db !(primIO $ prim__bindText stmt 1 body)
      | Left e => pure (Left e)
    Right () <- check db !(primIO $ prim__bindBlob stmt 2 bytes (cast n))
      | Left e => pure (Left e)
    rc <- primIO $ prim__step stmt
    if rc == sqliteDone then pure (Right ()) else Left <$> lastError db rc

Note : Type
Note = (Int64, Maybe String, List Bits8)

listNotes : HasIO io => Db -> io (Either SqlError (List Note))
listNotes db = withStmt db "SELECT id, body, data FROM notes ORDER BY id" (go [])
  where
    go : List Note -> Stmt -> io (Either SqlError (List Note))
    go acc stmt = do
      rc <- primIO $ prim__step stmt
      if rc == sqliteDone then pure (Right (reverse acc)) else
        if rc /= sqliteRow then Left <$> lastError db rc else do
          i <- primIO $ prim__columnInt stmt 0
          t <- columnText stmt 1
          bs <- maybe (pure []) bufferData' !(columnBlob stmt 2)
          go ((i, t, bs) :: acc) stmt
```

## 8. A callback into Idris2i-1

`exec` takes an Idris2i-1 function in `IO`; `toPrim` turns its result into the `PrimIO` that
the foreign type wants. The error message of `sqlite3_exec` is an out-parameter that the
caller frees with `sqlite3_free`: read from the cell, copied, freed.

```idris
exec : HasIO io => Db -> String -> (String -> String -> IO Int32) ->
       io (Either SqlError ())
exec db sql row = do
  cell <- primIO $ prim__newCell 1 8
  rc <- primIO $ prim__exec db.handle sql (\c, v => toPrim (row c v)) cell
  let msgPtr : AnyPtr = getField cell "p"
  r <- if rc == sqliteOk
          then pure (Right ())
          else do msg <- if prim__nullAnyPtr msgPtr /= 0
                            then pure "(no message)"
                            else primIO $ prim__copyString (prim__castPtr msgPtr)
                  primIO $ prim__sqliteFree msgPtr
                  pure (Left (MkSqlError rc msg))
  primIO $ prim__freeCell cell
  pure r
```

## 9. A struct of libc: `struct tm`

`Struct` describes every field of a C struct, in order, with the C types of the Idris2i-1
ones (`Int` is `int` here). This is the `struct tm` of glibc, musl and macOS. `setField`
writes in IO; `getField` reads; `strftime` writes into a `Buffer`. The same code ran with
Chez.

```idris
namespace Tm
  public export   -- the alias must reduce where the foreign types are read
  Tm : Type
  Tm = Struct "tm" [("tm_sec", Int), ("tm_min", Int), ("tm_hour", Int),
                    ("tm_mday", Int), ("tm_mon", Int), ("tm_year", Int),
                    ("tm_wday", Int), ("tm_yday", Int), ("tm_isdst", Int),
                    ("tm_gmtoff", Int64), ("tm_zone", Ptr String)]

  %foreign "C:calloc,libc,stdlib.h"
  prim__allocTm : Int -> Int -> PrimIO Tm

  %foreign "C:free,libc,stdlib.h"
  prim__freeTm : Tm -> PrimIO ()

  %foreign "C:strftime,libc,time.h"
  prim__strftime : Buffer -> Int -> String -> Tm -> PrimIO Int

  %foreign "C:timegm,libc,time.h"
  prim__timegm : Tm -> PrimIO Int64

  export
  demo : IO ()
  demo = do
    tm <- primIO $ prim__allocTm 1 64     -- at least sizeof(struct tm)
    setField tm "tm_year" (the Int 124)
    setField tm "tm_mon" (the Int 1)
    setField tm "tm_mday" (the Int 29)
    setField tm "tm_hour" (the Int 12)
    t <- primIO $ prim__timegm tm         -- also fills tm_wday and tm_yday
    printLn t
    printLn (the Int (getField tm "tm_wday"), the Int (getField tm "tm_yday"))
    Just buf <- newBuffer 64 | Nothing => putStrLn "no memory"
    n <- primIO $ prim__strftime buf 64 "%A %d %B %Y, %H:%M" tm
    putStrLn !(getString buf 0 n)
    primIO $ prim__freeTm tm
```

## 10. The program and its output

```idris
showNote : Note -> String
showNote (i, t, bs) = show i ++ " " ++ fromMaybe "NULL" t ++ " " ++ show bs

main : IO ()
main = do
  putStrLn ("SQLite " ++ libVersion)
  Left e <- openDb "/no/such/dir/notes.db"
    | Right _ => putStrLn "opened?"
  putStrLn (show e)
  Right db <- openDb ":memory:"
    | Left e => putStrLn (show e)
  Right () <- exec db "CREATE TABLE notes(id INTEGER PRIMARY KEY, body TEXT, data BLOB)"
                (\_, _ => pure 0)
    | Left e => putStrLn (show e)
  Just bytes <- newBuffer 3 | Nothing => putStrLn "no memory"
  setBits8 bytes 0 1
  setBits8 bytes 1 2
  setBits8 bytes 2 255
  Right () <- insertNote db "first note" bytes | Left e => putStrLn (show e)
  Right () <- insertNote db "second, λ" bytes | Left e => putStrLn (show e)
  Right () <- exec db "INSERT INTO notes(body) VALUES (NULL)" (\_, _ => pure 0)
    | Left e => putStrLn (show e)
  Right notes <- listNotes db | Left e => putStrLn (show e)
  traverse_ (putStrLn . showNote) notes
  Left e <- withStmt db "SELEC id FROM notes" (\_ => pure (Right ()))
    | Right () => putStrLn "prepared?"
  putStrLn (show e)
  Left e <- exec db "SELECT id, body FROM notes" (\col, val => do
                putStrLn (col ++ " = " ++ val)
                pure (if val == "2" then 1 else 0))
    | Right () => putStrLn "not stopped?"
  putStrLn (show e)
  Tm.demo
```

```text
SQLite 3.53.4
(closing the database)
error 14: unable to open database file
1 first note [1, 2, 255]
2 second, λ [1, 2, 255]
3 NULL []
error 1: near "SELEC": syntax error
id = 1
body = first note
id = 2
(closing the database)
error 4: query aborted
1709208000
(4, 59)
Thursday 29 February 2024, 12:00
```

Note where `(closing the database)` comes: with RefC a finaliser runs as soon as the
last reference to the pointer goes, here right after `openDb` returns its `Left`, and
right after the last use of `db`, before `main` prints the error. Do not rely on a
finaliser running late.

`IDRIS2I_1_REFC_LEAKCHECK=1 ./build/exec/notes` reports `0 leaked values`, and
`valgrind --leak-check=full` reports no errors and nothing definitely lost.

## 11. With Chez

This binding is for RefC: `glue_row` uses `runtime.h`, and Chez gives C a real function
pointer instead of a closure, so a Chez binding of `sqlite3_exec` needs a callback of
the C type and no trampoline (see `backends.md`, which has one that ran with both). The
glue would be a shared library (`cc -shared -fPIC -o libsqlite_glue.so ...`), found at
build time in the current directory or `IDRIS2I_1_LIBS` and then copied into
`build/exec/notes_app/`. The SQLite part was not run with Chez; the `struct tm` part
was, unchanged, and printed the same three lines.
