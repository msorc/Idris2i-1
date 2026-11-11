#include "prim.h"
#include "refc_util.h"
#include <string.h>
#include <unistd.h>

Idris2_Value *idris2_Data_IORef_prim__newIORef(Idris2_Value *erased,
                                               Idris2_Value *input_value,
                                               Idris2_Value *_world) {
  Idris2_IORef *ioRef = IDRIS2_NEW_VALUE(Idris2_IORef);
  ioRef->header.tag = IOREF_TAG;
  ioRef->lock = 0;
  ioRef->v = idris2_newReference(input_value);
  return (Idris2_Value *)ioRef;
}

Idris2_Value *idris2_readSharedIORef(Idris2_IORef *ioref) {
  idris2_spinLock(&ioref->lock);
  Idris2_Value *v = idris2_newReference(ioref->v);
  idris2_spinUnlock(&ioref->lock);
  return v;
}

Idris2_Value *idris2_Data_IORef_prim__writeIORef(Idris2_Value *erased,
                                                 Idris2_Value *_ioref,
                                                 Idris2_Value *new_value,
                                                 Idris2_Value *_world) {
  Idris2_IORef *ioref = (Idris2_IORef *)_ioref;
  idris2_newReference(new_value);
  Idris2_Value *old;
  if (idris2_isShared(_ioref)) {
    // Other threads see the value from now on.
    idris2_markShared(new_value);
    idris2_spinLock(&ioref->lock);
    old = ioref->v;
    ioref->v = new_value;
    idris2_spinUnlock(&ioref->lock);
  } else {
    old = ioref->v;
    ioref->v = new_value;
  }
  idris2_removeReference(old);
  return NULL;
}

// -----------------------------------
//       System operations
// -----------------------------------

#ifdef _WIN32
#define IDRIS2_OS_NAME "windows"
#elif _WIN64
#define IDRIS2_OS_NAME "windows"
#elif __APPLE__ || __MACH__
#define IDRIS2_OS_NAME "macOS"
#elif __linux__
#define IDRIS2_OS_NAME "Linux"
#elif __FreeBSD__
#define IDRIS2_OS_NAME "FreeBSD"
#elif __OpenBSD__
#define IDRIS2_OS_NAME "OpenBSD"
#elif __NetBSD__
#define IDRIS2_OS_NAME "NetBSD"
#elif __DragonFly__
#define IDRIS2_OS_NAME "DragonFly"
#elif __unix || __unix__
#define IDRIS2_OS_NAME "Unix"
#else
#define IDRIS2_OS_NAME "Other"
#endif
Idris2_ShortString const idris2_predefined_osstring = {
    IDRIS2_STOCKVAL(STRING_TAG), sizeof(IDRIS2_OS_NAME) - 1, IDRIS2_OS_NAME};

// NOTE: The codegen is obviously determined at compile time,
//       so the backend should optimize it by replacing it with a constant.
//       It would probably also be useful for conditional compilation.
Idris2_ShortString const idris2_predefined_codegenstring = {
    IDRIS2_STOCKVAL(STRING_TAG), 4, "refc"};

Idris2_Value *idris2_crash(Idris2_Value *msg) {
  Idris2_String *str = (Idris2_String *)msg;
  printf("ERROR: %s\n", str->str);
  exit(-1);
}

//
//
//
// // -----------------------------------
// //         Array operations
// // -----------------------------------

Idris2_Value *idris2_Data_IOArray_Prims_prim__newArray(Idris2_Value *erased,
                                                       Idris2_Value *_length,
                                                       Idris2_Value *v,
                                                       Idris2_Value *_word) {
  int length = idris2_vp_to_Int64(_length);
  Idris2_Array *a = idris2_makeArray(length);

  for (int i = 0; i < length; i++) {
    a->arr[i] = idris2_newReference(v);
  }

  return (Idris2_Value *)a;
}

Idris2_Value *idris2_Data_IOArray_Prims_prim__arraySet(Idris2_Value *erased,
                                                       Idris2_Value *_array,
                                                       Idris2_Value *index,
                                                       Idris2_Value *v,
                                                       Idris2_Value *_word) {
  Idris2_Array *a = (Idris2_Array *)_array;
  int64_t i = idris2_vp_to_Int64(index);
  idris2_newReference(v);
  Idris2_Value *old;
  if (idris2_isShared(_array)) {
    idris2_markShared(v);
    idris2_spinLock(&a->lock);
    old = a->arr[i];
    a->arr[i] = v;
    idris2_spinUnlock(&a->lock);
  } else {
    old = a->arr[i];
    a->arr[i] = v;
  }
  idris2_removeReference(old);
  return NULL;
}

Idris2_Value *idris2_sharedArrayGet(Idris2_Array *a, int64_t i) {
  idris2_spinLock(&a->lock);
  Idris2_Value *v = idris2_newReference(a->arr[i]);
  idris2_spinUnlock(&a->lock);
  return v;
}

//
// -----------------------------------
//      Pointer operations
// -----------------------------------

Idris2_Value *idris2_Prelude_IO_prim__onCollect(Idris2_Value *_erased,
                                                Idris2_Value *_anyPtr,
                                                Idris2_Value *_freeingFunction,
                                                Idris2_Value *_world) {
  Idris2_GCPointer *retVal = IDRIS2_NEW_VALUE(Idris2_GCPointer);
  retVal->header.tag = GC_POINTER_TAG;
  retVal->p = (Idris2_Pointer *)idris2_newReference(_anyPtr);
  retVal->onCollectFct =
      (Idris2_Closure *)idris2_newReference(_freeingFunction);
  return (Idris2_Value *)retVal;
}

Idris2_Value *
idris2_Prelude_IO_prim__onCollectAny(Idris2_Value *_anyPtr,
                                     Idris2_Value *_freeingFunction,
                                     Idris2_Value *_world) {
  Idris2_GCPointer *retVal = IDRIS2_NEW_VALUE(Idris2_GCPointer);
  retVal->header.tag = GC_POINTER_TAG;
  retVal->p = (Idris2_Pointer *)idris2_newReference(_anyPtr);
  retVal->onCollectFct =
      (Idris2_Closure *)idris2_newReference(_freeingFunction);
  return (Idris2_Value *)retVal;
}

char const idris2_constr_Int[] = "Int";
char const idris2_constr_Int8[] = "Int8";
char const idris2_constr_Int16[] = "Int16";
char const idris2_constr_Int32[] = "Int32";
char const idris2_constr_Int64[] = "Int64";
char const idris2_constr_Bits8[] = "Bits8";
char const idris2_constr_Bits16[] = "Bits16";
char const idris2_constr_Bits32[] = "Bits32";
char const idris2_constr_Bits64[] = "Bits64";
char const idris2_constr_Double[] = "Double";
char const idris2_constr_Integer[] = "Integer";
char const idris2_constr_Char[] = "Char";
char const idris2_constr_String[] = "String";
char const idris2_constr____gt[] = "->";
