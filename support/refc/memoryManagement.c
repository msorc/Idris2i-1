#include <stdbool.h>

#if defined(__has_include)
#if __has_include(<valgrind/valgrind.h>)
#include <valgrind/valgrind.h>
#define IDRIS2_HAVE_VALGRIND 1
#endif
#endif

#include "_datatypes.h"
#include "refc_util.h"
#include "runtime.h"

#if 0
// n_newReference, n_actualNewReference, n_immortalized, n_removeReference and
// n_tried_to_kill_immortals are not counted any more: the reference counting
// is inlined (see memoryManagement.h).
struct {
  unsigned int n_newValue;
  unsigned int n_newReference;
  unsigned int n_actualNewReference;
  unsigned int n_immortalized;
  unsigned int n_removeReference;
  unsigned int n_tried_to_kill_immortals;
  unsigned int n_freed;
} idris2_memory_stat = {0, 0, 0, 0, 0, 00, 0};
#define IDRIS2_INC_MEMSTAT(x)                                                  \
  do {                                                                         \
    ++(idris2_memory_stat.x);                                                  \
  } while (0)

void idris2_dumpMemoryStats(void) {
  fprintf(
      stderr,
      "n_newValue = %u\n"
      "n_newReference = %u\n"
      "n_actualNewReference = %u\n"
      "n_immortalized = %u\n"
      "n_removeReference = %u\n"
      "n_tried_to_kill_immortals = %u\n"
      "n_freed = %u\n",
      idris2_memory_stat.n_newValue, idris2_memory_stat.n_newReference,
      idris2_memory_stat.n_actualNewReference,
      idris2_memory_stat.n_immortalized, idris2_memory_stat.n_removeReference,
      idris2_memory_stat.n_tried_to_kill_immortals, idris2_memory_stat.n_freed);
}

#else
#define IDRIS2_INC_MEMSTAT(x)
// don't inline this, Because IDRIS2_MEMSTAT works only at compiling support
// libraries to suppressing overhead.
void idris2_dumpMemoryStats() {}
#endif

/*
 * Small values are allocated from pages of IDRIS2_PAGE_SIZE bytes, aligned
 * on their size, each holding values of one size class (a multiple of
 * IDRIS2_ALLOC_UNIT bytes).  Like in mimalloc, every page has a free list of
 * its own, and a class allocates from one page at a time: values allocated
 * one after the other end up close to each other, which matters a lot for
 * the caches (a single free list per class ends up as a random permutation
 * of all the memory that the class ever used).  This is much faster than
 * malloc and free, which the program calls for nearly every value.
 *
 * The class of a value is kept in the `reserved` byte of its header; 0 means
 * that the value comes from malloc (a large value, or a value allocated when
 * the pools are disabled).  A freed value goes back to the free list of its
 * page, found by masking its address.  The pages are never given back to
 * the system, they are reused for new values.
 *
 * Every value is allocated and freed by the same OS thread (green threads
 * all run on one), so the pages need no locking.
 *
 * Compile the support library with -DIDRIS2_REFC_NO_POOLS to allocate every
 * value with malloc, e.g. to look for leaks with a memory checker.
 */

static void *allocAligned(size_t alignment, size_t size) {
  size = ((size + alignment - 1) / alignment) * alignment;
#if defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L) &&              \
    !defined(__APPLE__) && !defined(_WIN32)
  void *retVal = aligned_alloc(alignment, size);
#elif ((defined(_POSIX_C_SOURCE) && (_POSIX_C_SOURCE >= 200112L)) ||           \
       (defined(_XOPEN_SOURCE) && (_XOPEN_SOURCE >= 600))) &&                  \
    !defined(_WIN32)
  void *retVal = NULL;
  if (posix_memalign(&retVal, alignment, size) != 0)
    retVal = NULL;
#else
  void *retVal = alignment <= sizeof(void *) ? malloc(size) : NULL;
#endif
  IDRIS2_REFC_VERIFY(retVal && !idris2_vp_is_unboxed(retVal), "malloc failed");
  return retVal;
}

Idris2_SizeClass idris2_classes[IDRIS2_ALLOC_CLASSES + 1];

static Idris2_Page *newPage(unsigned cls) {
  Idris2_Page *page = allocAligned(IDRIS2_PAGE_SIZE, IDRIS2_PAGE_SIZE);
  size_t size = (size_t)cls * IDRIS2_ALLOC_UNIT;
  // The values start after the header of the page, aligned on 16 bytes.
  char *start = (char *)page + ((sizeof(Idris2_Page) + 15) & ~(size_t)15);
  page->free = NULL;
  page->bump = start;
  page->end = start + (((char *)page + IDRIS2_PAGE_SIZE - start) / size) * size;
  page->nextAvailable = NULL;
  page->available = 1;
  return page;
}

// Under Valgrind every value comes from malloc, so that it can check them:
// the pages are never used (the current page of every class stays NULL, so
// every allocation comes here).
static int runningOnValgrind(void) {
#ifdef IDRIS2_HAVE_VALGRIND
  static int known = 0, running = 0;
  if (!known) {
    running = RUNNING_ON_VALGRIND ? 1 : 0;
    known = 1;
  }
  return running;
#else
  return 0;
#endif
}

Idris2_Value *idris2_allocSlow(unsigned cls) {
  if (runningOnValgrind()) {
    // A value from malloc: its class is 0.
    return idris2_allocLarge((size_t)cls * IDRIS2_ALLOC_UNIT);
  }
  Idris2_SizeClass *c = &idris2_classes[cls];
  if (c->current)
    c->current->available = 0;
  Idris2_Page *page = c->available;
  if (page) {
    c->available = page->nextAvailable;
  } else {
    page = newPage(cls);
  }
  c->current = page;
  page->available = 1;
  Idris2_Value *retVal;
  Idris2_FreeValue *v = page->free;
  if (v) {
    page->free = v->next;
    retVal = (Idris2_Value *)v;
  } else {
    retVal = (Idris2_Value *)page->bump;
    page->bump += (size_t)cls * IDRIS2_ALLOC_UNIT;
  }
  retVal->header.reserved = (uint8_t)cls;
  retVal->header.refCounter = 1;
  retVal->header.tag = NO_TAG;
  return retVal;
}

Idris2_Value *idris2_allocLarge(size_t size) {
  Idris2_Value *retVal = (Idris2_Value *)allocAligned(sizeof(void *), size);
  retVal->header.reserved = 0;
  retVal->header.refCounter = 1;
  retVal->header.tag = NO_TAG;
  return retVal;
}

void idris2_freeValue(Idris2_Value *value) {
  unsigned cls = value->header.reserved;
  if (cls == 0) {
    free(value);
    return;
  }
  Idris2_Page *page =
      (Idris2_Page *)((uintptr_t)value & ~(uintptr_t)(IDRIS2_PAGE_SIZE - 1));
  Idris2_FreeValue *v = (Idris2_FreeValue *)value;
  v->next = page->free;
  page->free = v;
  if (!page->available) {
    // The page was full and had been left: make it available again.
    Idris2_SizeClass *c = &idris2_classes[cls];
    page->available = 1;
    page->nextAvailable = c->available;
    c->available = page;
  }
}

Idris2_Value *idris2_newZeroedValue(size_t size) {
  Idris2_Value *value = idris2_newValue(size);
  // Clear the payload, but leave the header alone: it holds the reference
  // count and the tag.
  if (size > sizeof(Idris2_header)) {
    memset((char *)value + sizeof(Idris2_header), 0,
           size - sizeof(Idris2_header));
  }
  return value;
}


Idris2_Value *idris2_mkBits32_Boxed(uint32_t i) {
  Idris2_Bits32 *retVal = IDRIS2_NEW_VALUE(Idris2_Bits32);
  retVal->header.tag = BITS32_TAG;
  retVal->ui32 = i;
  return (Idris2_Value *)retVal;
}


Idris2_Value *idris2_mkInt32_Boxed(int32_t i) {
  Idris2_Int32 *retVal = IDRIS2_NEW_VALUE(Idris2_Int32);
  retVal->header.tag = INT32_TAG;
  retVal->i32 = i;
  return (Idris2_Value *)retVal;
}


Idris2_Integer *idris2_mkInteger() {
  Idris2_Integer *retVal = IDRIS2_NEW_VALUE(Idris2_Integer);
  retVal->header.tag = INTEGER_TAG;
  mpz_init(retVal->i);
  return retVal;
}

Idris2_Value *idris2_mkIntegerLiteral(char *i) {
  Idris2_Integer *retVal = idris2_mkInteger();
  mpz_set_str(retVal->i, i, 10);
  return (Idris2_Value *)retVal;
}

Idris2_String *idris2_mkEmptyString(size_t l) {
  if (l == 1)
    return (Idris2_String *)&idris2_predefined_nullstring;

  Idris2_String *retVal = IDRIS2_NEW_VALUE(Idris2_String);
  retVal->header.tag = STRING_TAG;
  retVal->str = malloc(l);
  memset(retVal->str, 0, l);
  return retVal;
}

Idris2_String *idris2_mkStringOwned(char *s) {
  if (s[0] == '\0') {
    free(s);
    return (Idris2_String *)&idris2_predefined_nullstring;
  }

  Idris2_String *retVal = IDRIS2_NEW_VALUE(Idris2_String);
  retVal->header.tag = STRING_TAG;
  retVal->str = s;
  return retVal;
}

Idris2_String *idris2_mkString(char *s) {
  if (s[0] == '\0')
    return (Idris2_String *)&idris2_predefined_nullstring;

  Idris2_String *retVal = IDRIS2_NEW_VALUE(Idris2_String);
  int l = strlen(s);
  retVal->header.tag = STRING_TAG;
  retVal->str = malloc(l + 1);
  memset(retVal->str, 0, l + 1);
  memcpy(retVal->str, s, l);
  return retVal;
}

Idris2_Pointer *idris2_makePointer(void *ptr_Raw) {
  Idris2_Pointer *p = IDRIS2_NEW_VALUE(Idris2_Pointer);
  p->header.tag = POINTER_TAG;
  p->p = ptr_Raw;
  return p;
}

Idris2_GCPointer *idris2_makeGCPointer(void *ptr_Raw,
                                       Idris2_Closure *onCollectFct) {
  Idris2_GCPointer *p = IDRIS2_NEW_VALUE(Idris2_GCPointer);
  p->header.tag = GC_POINTER_TAG;
  p->p = idris2_makePointer(ptr_Raw);
  p->onCollectFct = onCollectFct;
  return p;
}

Idris2_Buffer *idris2_makeBuffer(void *buf) {
  Idris2_Buffer *b = IDRIS2_NEW_VALUE(Idris2_Buffer);
  b->header.tag = BUFFER_TAG;
  b->buffer = buf;
  return b;
}

Idris2_Array *idris2_makeArray(int length) {
  Idris2_Array *a = IDRIS2_NEW_VALUE(Idris2_Array);
  a->header.tag = ARRAY_TAG;
  a->capacity = length;
  a->arr = (Idris2_Value **)malloc(sizeof(Idris2_Value *) * length);
  memset(a->arr, 0, sizeof(Idris2_Value *) * length);
  return a;
}

// The last reference to `elem` is gone: release what it refers to, and free
// it.  The common cases of idris2_removeReference are inlined (see
// memoryManagement.h).
void idris2_releaseValue(Idris2_Value *elem) {
  // The last field of a constructor or a closure is released by looping
  // rather than by a recursive call: freeing a long list (the tail is the
  // last field) does not need a deep stack.
  for (;;) {
    Idris2_Value *last = NULL;
    IDRIS2_INC_MEMSTAT(n_freed);
    switch (elem->header.tag) {
    case BITS32_TAG:
    case BITS64_TAG:
    case INT32_TAG:
    case INT64_TAG:
      /* nothing to delete, added for sake of completeness */
      break;
    case INTEGER_TAG:
      mpz_clear(((Idris2_Integer *)elem)->i);
      break;

    case DOUBLE_TAG:
      /* nothing to delete, added for sake of completeness */
      break;

    case STRING_TAG:
      free(((Idris2_String *)elem)->str);
      break;

    case CLOSURE_TAG: {
      Idris2_Closure *cl = (Idris2_Closure *)elem;
      if (cl->filled > 0) {
        for (int i = 0; i < cl->filled - 1; ++i)
          idris2_removeReference(cl->args[i]);
        last = cl->args[cl->filled - 1];
      }
      break;
    }

    case CONSTRUCTOR_TAG: {
      Idris2_Constructor *constr = (Idris2_Constructor *)elem;
      if (constr->total > 0) {
        for (int i = 0; i < constr->total - 1; i++)
          idris2_removeReference(constr->args[i]);
        last = constr->args[constr->total - 1];
      }
      break;
    }
    case IOREF_TAG:
      idris2_removeReference(((Idris2_IORef *)elem)->v);
      break;

    case BUFFER_TAG: {
      Idris2_Buffer *b = (Idris2_Buffer *)elem;
      free(b->buffer);
      break;
    }

    case ARRAY_TAG: {
      Idris2_Array *a = (Idris2_Array *)elem;
      for (int i = 0; i < a->capacity; i++) {
        idris2_removeReference(a->arr[i]);
      }
      free(a->arr);
      break;
    }
    case POINTER_TAG:
      /* nothing to delete, added for sake of completeness */
      break;

    case GC_POINTER_TAG: {
      /* Run the finaliser.  Applying a closure consumes both the closure and
         its argument, so the references held by the GC pointer are handed
         over to the finaliser. */
      Idris2_GCPointer *vPtr = (Idris2_GCPointer *)elem;
      /* The finaliser may run while the caller has a pending tail call (see
         runtime.h): keep it. */
      Idris2_PendingTailCall pending = idris2_pendingTailCall;
      Idris2_Value *closure1 = idris2_apply_closure(
          (Idris2_Value *)vPtr->onCollectFct, (Idris2_Value *)vPtr->p);
      idris2_removeReference(idris2_apply_closure(closure1, NULL));
      idris2_pendingTailCall = pending;
      break;
    }

    case CHANNEL_TAG: {
      /* Nobody can be waiting on a channel that is being freed: a waiting
         thread holds a reference to it. */
      Idris2_Channel *channel = (Idris2_Channel *)elem;
      if (channel->full)
        idris2_removeReference(channel->value);
      break;
    }

    case THREAD_ID_TAG:
      /* The thread clears the handle when it finishes, and it holds a
         reference to the handle until then. */
      break;

    default:
      break;
    }
    // finally, free element
    idris2_freeValue(elem);

    // Release the last field, here when it was its last reference.
    if (!last || idris2_vp_is_unboxed(last) ||
        last->header.refCounter == IDRIS2_VP_REFCOUNTER_MAX)
      return;
    if (last->header.refCounter != 1) {
      --last->header.refCounter;
      return;
    }
    elem = last;
  }
}

// /////////////////////////////////////////////////////////////////////////
// PRE-DEFINED VLAUES

#define IDRIS2_MK_PREDEFINED_INT_10(t, n)                                      \
  {IDRIS2_STOCKVAL(t), (n + 0)}, {IDRIS2_STOCKVAL(t), (n + 1)},                \
      {IDRIS2_STOCKVAL(t), (n + 2)}, {IDRIS2_STOCKVAL(t), (n + 3)},            \
      {IDRIS2_STOCKVAL(t), (n + 4)}, {IDRIS2_STOCKVAL(t), (n + 5)},            \
      {IDRIS2_STOCKVAL(t), (n + 6)}, {IDRIS2_STOCKVAL(t), (n + 7)},            \
      {IDRIS2_STOCKVAL(t), (n + 8)}, {                                         \
    IDRIS2_STOCKVAL(t), (n + 9)                                                \
  }
Idris2_Int64 const idris2_predefined_Int64[100] = {
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 0),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 10),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 20),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 30),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 40),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 50),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 60),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 70),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 80),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 90)};

Idris2_Bits64 const idris2_predefined_Bits64[100] = {
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 0),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 10),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 20),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 30),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 40),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 50),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 60),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 70),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 80),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 90)};

Idris2_String const idris2_predefined_nullstring = {IDRIS2_STOCKVAL(STRING_TAG),
                                                    ""};

static bool idris2_predefined_integer_initialized = false;
Idris2_Integer idris2_predefined_Integer[100];

Idris2_Value *idris2_makeIntegerConstant(Idris2_Value **slot,
                                         char const *digits) {
  Idris2_Integer *value = idris2_mkInteger();
  mpz_set_str(value->i, digits, 10);
  value->header.refCounter = IDRIS2_VP_REFCOUNTER_MAX;
  *slot = (Idris2_Value *)value;
  return *slot;
}

Idris2_Value *idris2_getPredefinedInteger(int n) {
  IDRIS2_REFC_VERIFY(n >= 0 && n < 100,
                     "invalid range of predefined integers.");

  if (!idris2_predefined_integer_initialized) {
    idris2_predefined_integer_initialized = true;
    for (int i = 0; i < 100; ++i) {
      idris2_predefined_Integer[i].header.refCounter = IDRIS2_VP_REFCOUNTER_MAX;
      idris2_predefined_Integer[i].header.tag = INTEGER_TAG;
      idris2_predefined_Integer[i].header.reserved = 0;

      mpz_init(idris2_predefined_Integer[i].i);
      mpz_set_si(idris2_predefined_Integer[i].i, i);
    }
  }
  return (Idris2_Value *)&idris2_predefined_Integer[n];
}
