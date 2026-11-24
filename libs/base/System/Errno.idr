||| Managing error codes.
module System.Errno

%default total

%foreign "C:idris2i_1_getErrno, libidris2i_1_support, idris_support.h"
         "node:support:getErrno,support_system"
prim__getErrno : PrimIO Int

%foreign "C:idris2i_1_strerror, libidris2i_1_support, idris_support.h"
         "node:support:strerror,support_system"
prim__strerror : Int -> PrimIO String

||| Fetch libc `errno` global variable.
||| This sometimes returns 0 on windows.
export
getErrno : HasIO io => io Int
getErrno = primIO prim__getErrno

||| Convert numeric `errno` to string.
export
strerror : Int -> String
strerror errno = unsafePerformIO $ primIO $ prim__strerror errno
