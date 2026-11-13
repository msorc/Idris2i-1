#include <limits.h>
#include <stdbool.h>

#if defined(__unix__) || defined(__APPLE__)
#include <sys/mman.h>
#include <unistd.h>
#endif

#if defined(__has_include)
#if __has_include(<valgrind/valgrind.h>)
#include <valgrind/valgrind.h>
#define IDRIS2_HAVE_VALGRIND 1
#endif
#endif

#include "_datatypes.h"
#include "refc_util.h"
#include "runtime.h"

// Every page, for the reports at exit (see idris2_reportAtExit).  Pages are
// made rarely (one per 64KB), so a lock is fine.
static Idris2_Page *allPages = NULL;
static Idris2_SpinLock allPagesLock = 0;

// The values from malloc that are not freed yet.
static int64_t largeLive = 0;

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
 * page, found by masking its address.  A page that holds no value any more
 * goes to the empty pages of its worker, from which any class can take it;
 * beyond idris2_keepPages of them, the memory of the page goes back to the
 * system (madvise), and the page is kept to be used again (see freeLocal).
 *
 * Every worker (see worker.h) has pages of its own, and only allocates from
 * them, so allocating takes no lock.  A value may be freed by another worker
 * than the one that allocated it (green threads move between workers, and
 * shared values are seen by several of them): it is then pushed on a list of
 * the worker that owns its page, without a lock, and that worker puts it
 * back in its page the next time that it needs a page.
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

// The values of a page start after its header, aligned on 16 bytes.
static inline char *pageStart(Idris2_Page *page) {
  return (char *)page + ((sizeof(Idris2_Page) + 15) & ~(size_t)15);
}

int idris2_keepPages = 16;

// The pages that hold values (peak: the most at any time), over all workers.
// Pages are taken and emptied rarely (64KB at a time), so this is atomic.
static int64_t pagesInUse = 0, peakPagesInUse = 0;

static void pageTaken(void) {
  int64_t n = __atomic_add_fetch(&pagesInUse, 1, __ATOMIC_RELAXED);
  int64_t peak = __atomic_load_n(&peakPagesInUse, __ATOMIC_RELAXED);
  while (n > peak &&
         !__atomic_compare_exchange_n(&peakPagesInUse, &peak, n, 1,
                                      __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {
  }
}

// Make an empty page hold values of the class `cls`, for the worker `w`.
static void initPage(Idris2_Page *page, Idris2_Worker *w, unsigned cls) {
  size_t size = (size_t)cls * IDRIS2_ALLOC_UNIT;
  char *start = pageStart(page);
  page->owner = w;
  page->cls = cls;
  page->free = NULL;
  page->bump = start;
  page->end = start + (((char *)page + IDRIS2_PAGE_SIZE - start) / size) * size;
  page->live = 0;
  page->nextAvailable = page->prevAvailable = NULL;
  page->available = 1;
  // (the system gives back zeroed memory on the first touch: nothing reads
  // the values that the bump allocator has not handed out)
  page->decommitted = 0;
  pageTaken();
}

static Idris2_Page *newPage(Idris2_Worker *w, unsigned cls) {
  Idris2_Page *page = allocAligned(IDRIS2_PAGE_SIZE, IDRIS2_PAGE_SIZE);
  initPage(page, w, cls);
  idris2_spinLock(&allPagesLock);
  page->nextPage = allPages;
  allPages = page;
  idris2_spinUnlock(&allPagesLock);
  IDRIS2_STAT(pagesCreated);
  return page;
}

// Give the memory of an empty page back to the system, but its header.
// Returns 0 when this is not possible.
static int decommitPage(Idris2_Page *page) {
#if (defined(__unix__) || defined(__APPLE__)) && !defined(IDRIS2_REFC_NO_POOLS)
  static size_t osPage = 0;
  if (!osPage) {
    long n = sysconf(_SC_PAGESIZE);
    osPage = n > 0 ? (size_t)n : IDRIS2_PAGE_SIZE;
  }
  size_t header = (sizeof(Idris2_Page) + osPage - 1) / osPage * osPage;
  if (header >= IDRIS2_PAGE_SIZE)
    return 0;
  if (madvise((char *)page + header, IDRIS2_PAGE_SIZE - header,
              MADV_DONTNEED) != 0)
    return 0;
  page->decommitted = 1;
  return 1;
#else
  (void)page;
  return 0;
#endif
}

// The empty pages that any worker can take, beyond those that the workers
// keep (see pageEmptied): those that keep their memory, up to
// idris2_keepPages per worker, and those that gave it back.  A page that
// holds no value has no free in flight either (see freeLocal), so it can
// change its owner.
static Idris2_SpinLock poolLock = 0;
static Idris2_Page *poolPages = NULL, *poolDecommitted = NULL;
static int64_t poolCount = 0;
// Set when the program exits, under releaseLock: the workers stop touching
// their pages then (see idris2_releaseWorkerPages), so that the reports at
// exit can look at them.
static Idris2_SpinLock releaseLock = 0;
static int exiting = 0;

// Put the empty pages first .. last (linked by nextAvailable) in the pool.
static void poolPut(Idris2_Page *first, Idris2_Page *last) {
  int64_t keep = (int64_t)idris2_keepPages * idris2_workerCount();
  idris2_spinLock(&poolLock);
  for (Idris2_Page *page = first;;) {
    Idris2_Page *next = page->nextAvailable;
    if (poolCount >= keep && decommitPage(page)) {
      IDRIS2_STAT(pagesDecommitted);
      page->nextAvailable = poolDecommitted;
      poolDecommitted = page;
    } else {
      page->nextAvailable = poolPages;
      poolPages = page;
      poolCount++;
    }
    if (page == last)
      break;
    page = next;
  }
  idris2_spinUnlock(&poolLock);
}

static Idris2_Page *poolTake(void) {
  if (!__atomic_load_n(&poolPages, __ATOMIC_RELAXED) &&
      !__atomic_load_n(&poolDecommitted, __ATOMIC_RELAXED))
    return NULL;
  idris2_spinLock(&poolLock);
  Idris2_Page *page = poolPages;
  if (page) {
    poolPages = page->nextAvailable;
    poolCount--;
  } else if ((page = poolDecommitted) != NULL) {
    poolDecommitted = page->nextAvailable;
  }
  idris2_spinUnlock(&poolLock);
  return page;
}

// A page of `w` that holds no value any more, and is not the current page
// of its class: it goes to the empty pages of the worker, from which any
// class can take it.  Beyond idris2_keepPages of them, it goes to the pool
// of the workers; beyond idris2_keepPages per worker there, its memory goes
// back to the system.
#if defined(__GNUC__)
__attribute__((noinline, cold))
#endif
static void pageEmptied(Idris2_Worker *w, Idris2_Page *page) {
  Idris2_SizeClass *c = &w->classes[page->cls];
  if (page->available) {
    // (in the available list of its class: it is not the current page)
    if (page->prevAvailable)
      page->prevAvailable->nextAvailable = page->nextAvailable;
    else
      c->available = page->nextAvailable;
    if (page->nextAvailable)
      page->nextAvailable->prevAvailable = page->prevAvailable;
  }
  page->available = 0;
  page->cls = 0;
  page->free = NULL;
  page->bump = page->end = pageStart(page);
  page->prevAvailable = NULL;
  __atomic_sub_fetch(&pagesInUse, 1, __ATOMIC_RELAXED);
  IDRIS2_STAT(pagesEmptied);
  if (w->nEmpty >= idris2_keepPages) {
    // (to the pool, for the other workers)
    poolPut(page, page);
    return;
  }
  page->nextAvailable = w->emptyPages;
  w->emptyPages = page;
  w->nEmpty++;
}

// An empty page of `w` for the class `cls`, if it has one.
static Idris2_Page *takeEmptyPage(Idris2_Worker *w, unsigned cls) {
  Idris2_Page *page = w->emptyPages;
  if (page) {
    w->emptyPages = page->nextAvailable;
    w->nEmpty--;
  } else if (!(page = poolTake())) {
    return NULL;
  }
  IDRIS2_STAT(pagesReused);
  initPage(page, w, cls);
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

// Put a value of a page of `w` back in its page.
//
// The pages count the values that they hold (`live`) so that a page that
// holds none can go to another class, or give its memory back.  To keep
// allocation fast, only the frees are counted: the current page of a class
// (the only one that values are allocated from) counts its frees, but its
// count means nothing; when it stops being the current page, it is full,
// and its count becomes the number of its values (see idris2_allocSlow).  A
// page is only emptied when it is not the current one.  A value that another
// worker frees counts until its owner puts it back (collectRemoteFrees), so
// a page that holds no value is not waiting for any free either.
IDRIS2_INLINE void freeLocal(Idris2_Worker *w, Idris2_Page *page,
                      Idris2_FreeValue *v) {
  if (__builtin_expect(--page->live == 0, 0) &&
      page != w->classes[page->cls].current) {
    pageEmptied(w, page);
    return;
  }
  v->next = page->free;
  page->free = v;
  if (__builtin_expect(!page->available, 0)) {
    Idris2_SizeClass *c = &w->classes[page->cls];
    // The page was full and had been left: make it available again.
    page->available = 1;
    page->prevAvailable = NULL;
    page->nextAvailable = c->available;
    if (c->available)
      c->available->prevAvailable = page;
    c->available = page;
  }
}
static void collectRemoteFrees(Idris2_Worker *w);

void idris2_releaseWorkerPages(Idris2_Worker *w) {
  idris2_spinLock(&releaseLock);
  if (!exiting) {
    // (the values freed by other workers may empty some pages)
    collectRemoteFrees(w);
    Idris2_Page *first = w->emptyPages;
    if (first) {
      Idris2_Page *last = first;
      while (last->nextAvailable)
        last = last->nextAvailable;
      w->emptyPages = NULL;
      w->nEmpty = 0;
      IDRIS2_STAT(pagesToPool);
      poolPut(first, last);
    }
  }
  idris2_spinUnlock(&releaseLock);
}

// Put the values that other workers freed back in their pages.
static void collectRemoteFrees(Idris2_Worker *w) {
  if (!__atomic_load_n(&w->remoteFree, __ATOMIC_RELAXED))
    return;
  Idris2_FreeValue *v =
      __atomic_exchange_n(&w->remoteFree, NULL, __ATOMIC_ACQUIRE);
  while (v) {
    Idris2_FreeValue *next = v->next;
#ifdef IDRIS2_REFC_STATS
    ++w->stats.remoteFreesReceived;
#endif
    freeLocal(w,
              (Idris2_Page *)((uintptr_t)v &
                              ~(uintptr_t)(IDRIS2_PAGE_SIZE - 1)),
              v);
    v = next;
  }
}

Idris2_Value *idris2_allocSlow(unsigned cls) {
  if (runningOnValgrind()) {
    // A value from malloc: its class is 0.
    return idris2_allocLarge((size_t)cls * IDRIS2_ALLOC_UNIT);
  }
  Idris2_Worker *w = idris2_worker();
  collectRemoteFrees(w);
  Idris2_SizeClass *c = &w->classes[cls];
  Idris2_Page *page = c->current;
  // (the values that other workers freed may have gone back to the current
  // page)
  if (!page || (!page->free && page->bump >= page->end)) {
    if (page) {
      page->available = 0; // full: a free makes it available again
      // Every value of the page is allocated now, so this is the number of
      // values that it holds (the allocations do not count them, see
      // freeLocal).
      page->live = (uint32_t)((size_t)(page->end - pageStart(page)) /
                              ((size_t)cls * IDRIS2_ALLOC_UNIT));
    }
    page = c->available;
    if (page) {
      c->available = page->nextAvailable;
      if (c->available)
        c->available->prevAvailable = NULL;
      page->nextAvailable = NULL;
    } else if (!(page = takeEmptyPage(w, cls))) {
      page = newPage(w, cls);
    }
    c->current = page;
    page->available = 1;
  }
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
  IDRIS2_STAT(allocs[cls]);
  return retVal;
}

Idris2_Value *idris2_allocLarge(size_t size) {
  Idris2_Value *retVal = (Idris2_Value *)allocAligned(sizeof(void *), size);
  __atomic_fetch_add(&largeLive, 1, __ATOMIC_RELAXED);
  IDRIS2_STAT(largeAllocs);
  retVal->header.reserved = 0;
  retVal->header.refCounter = 1;
  retVal->header.tag = NO_TAG;
  return retVal;
}

void idris2_freeValue(Idris2_Value *value) {
  unsigned cls = value->header.reserved & IDRIS2_CLASS_MASK;
  if (cls == 0) {
    __atomic_fetch_sub(&largeLive, 1, __ATOMIC_RELAXED);
    IDRIS2_STAT(largeFrees);
    free(value);
    return;
  }
  IDRIS2_STAT(frees[cls]);
  Idris2_Page *page =
      (Idris2_Page *)((uintptr_t)value & ~(uintptr_t)(IDRIS2_PAGE_SIZE - 1));
  Idris2_FreeValue *v = (Idris2_FreeValue *)value;
  Idris2_Worker *w = idris2_worker();
  if (page->owner == w) {
    freeLocal(w, page, v);
    return;
  }
  // A value of another worker: hand it over to that worker.
  Idris2_Worker *owner = page->owner;
  Idris2_FreeValue *head = __atomic_load_n(&owner->remoteFree, __ATOMIC_RELAXED);
  do {
    v->next = head;
  } while (!__atomic_compare_exchange_n(&owner->remoteFree, &head, v, 1,
                                        __ATOMIC_RELEASE, __ATOMIC_RELAXED));
}

// ---------------------------------------------------------------------------
// Overflowed reference counts
//
// A count is 16 bits.  A value that has IDRIS2_VP_REFCOUNTER_OVERFLOW
// references, and gets more, keeps that count; the others are counted in a
// table, by address: its count is the one of the header plus the one of the
// table.  The fast paths of the reference counting only see counts below the
// overflow (see idris2_isPlainCounted), so the table is only reached from
// here.  A value that loses its extra references gets back on the fast path,
// and is released as any other.
//
// The table is shared by the workers, under a lock.  The count of a shared
// value only moves from or to the overflow under the lock, so that a value
// that the table counts always has the overflow count.
// ---------------------------------------------------------------------------

typedef struct {
  uintptr_t key; // 0: free
  uint64_t extra;
} OverflowEntry;

static OverflowEntry *overflowTable = NULL;
static size_t overflowCapacity = 0, overflowUsed = 0;
static Idris2_SpinLock overflowLock = 0;

static size_t overflowHash(uintptr_t key) {
  key ^= key >> 33;
  key *= 0xff51afd7ed558ccdULL;
  key ^= key >> 33;
  return (size_t)key;
}

static OverflowEntry *overflowFind(uintptr_t key) {
  if (!overflowCapacity)
    return NULL;
  for (size_t i = overflowHash(key) & (overflowCapacity - 1);;
       i = (i + 1) & (overflowCapacity - 1)) {
    if (overflowTable[i].key == key)
      return &overflowTable[i];
    if (overflowTable[i].key == 0)
      return NULL;
  }
}

static void overflowInsert(uintptr_t key, uint64_t extra) {
  if (2 * (overflowUsed + 1) > overflowCapacity) {
    size_t capacity = overflowCapacity ? 2 * overflowCapacity : 64;
    OverflowEntry *old = overflowTable;
    size_t oldCapacity = overflowCapacity;
    overflowTable = calloc(capacity, sizeof(OverflowEntry));
    IDRIS2_REFC_VERIFY(overflowTable, "malloc failed");
    overflowCapacity = capacity;
    overflowUsed = 0;
    for (size_t i = 0; i < oldCapacity; i++)
      if (old[i].key)
        overflowInsert(old[i].key, old[i].extra);
    free(old);
  }
  size_t i = overflowHash(key) & (overflowCapacity - 1);
  while (overflowTable[i].key)
    i = (i + 1) & (overflowCapacity - 1);
  overflowTable[i].key = key;
  overflowTable[i].extra = extra;
  overflowUsed++;
}

// Remove an entry, moving back the ones after it that it displaced (linear
// probing without tombstones).
static void overflowDelete(OverflowEntry *e) {
  size_t mask = overflowCapacity - 1;
  size_t i = (size_t)(e - overflowTable);
  for (size_t j = (i + 1) & mask; overflowTable[j].key; j = (j + 1) & mask) {
    size_t home = overflowHash(overflowTable[j].key) & mask;
    // Can the entry at j move to i?  Yes when its home is not in (i, j].
    if (i <= j ? (home <= i || home > j) : (home <= i && home > j)) {
      overflowTable[i] = overflowTable[j];
      i = j;
    }
  }
  overflowTable[i].key = 0;
  overflowUsed--;
}

// One more reference to a value at the overflow count (under the lock).
static void overflowAdd(Idris2_Value *v) {
  OverflowEntry *e = overflowFind((uintptr_t)v);
  if (e) {
    e->extra++;
  } else {
    overflowInsert((uintptr_t)v, 1);
    IDRIS2_STAT(overflows);
  }
}

// One reference less to a value at the overflow count (under the lock):
// returns 0 when the table counted none, and the count of the header has to
// go down.
static int overflowRemove(Idris2_Value *v) {
  OverflowEntry *e = overflowFind((uintptr_t)v);
  if (!e)
    return 0;
  if (--e->extra == 0)
    overflowDelete(e);
  return 1;
}

void idris2_forgetOverflow(Idris2_Value *v) {
  idris2_spinLock(&overflowLock);
  OverflowEntry *e = overflowFind((uintptr_t)v);
  if (e)
    overflowDelete(e);
  idris2_spinUnlock(&overflowLock);
}

// ---------------------------------------------------------------------------
// Shared values (see memoryManagement.h)
// ---------------------------------------------------------------------------

void idris2_newReferenceSlow(Idris2_Value *v) {
  // (immortal values, shared or not, are the common case here: the count of
  // an immortal value never changes, so a plain read will do)
  if (v->header.refCounter == IDRIS2_VP_REFCOUNTER_MAX) {
    IDRIS2_STAT(dup[IDRIS2_RC_IMMORTAL]);
    return;
  }
  if (!idris2_isShared(v)) {
    // at the overflow
    IDRIS2_STAT(dup[IDRIS2_RC_PLAIN]);
    idris2_spinLock(&overflowLock);
    overflowAdd(v);
    idris2_spinUnlock(&overflowLock);
    return;
  }
  IDRIS2_STAT(dup[IDRIS2_RC_SHARED]);
  uint16_t c = __atomic_load_n(&v->header.refCounter, __ATOMIC_RELAXED);
  for (;;) {
    if (c == IDRIS2_VP_REFCOUNTER_MAX)
      return;
    if (c == IDRIS2_VP_REFCOUNTER_OVERFLOW) {
      idris2_spinLock(&overflowLock);
      c = __atomic_load_n(&v->header.refCounter, __ATOMIC_RELAXED);
      if (c == IDRIS2_VP_REFCOUNTER_OVERFLOW) {
        overflowAdd(v);
        idris2_spinUnlock(&overflowLock);
        return;
      }
      idris2_spinUnlock(&overflowLock);
      continue;
    }
    if (__atomic_compare_exchange_n(&v->header.refCounter, &c, c + 1, 1,
                                    __ATOMIC_RELAXED, __ATOMIC_RELAXED))
      return;
  }
}

// Drop a reference to a shared value: 1 when it was the last one.
static int sharedDropReference(Idris2_Value *v) {
  uint16_t c = __atomic_load_n(&v->header.refCounter, __ATOMIC_ACQUIRE);
  // The only reference cannot be taken by anybody else.
  if (c == 1)
    return 1;
  for (;;) {
    if (c == IDRIS2_VP_REFCOUNTER_MAX)
      return 0;
    if (c == IDRIS2_VP_REFCOUNTER_OVERFLOW) {
      // (while the count is at the overflow, it only changes under the lock)
      idris2_spinLock(&overflowLock);
      c = __atomic_load_n(&v->header.refCounter, __ATOMIC_ACQUIRE);
      if (c == IDRIS2_VP_REFCOUNTER_OVERFLOW) {
        if (!overflowRemove(v))
          __atomic_store_n(&v->header.refCounter, c - 1, __ATOMIC_RELEASE);
        idris2_spinUnlock(&overflowLock);
        return 0;
      }
      idris2_spinUnlock(&overflowLock);
      continue;
    }
    if (__atomic_compare_exchange_n(&v->header.refCounter, &c, c - 1, 1,
                                    __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE))
      return c == 1;
  }
}

// A value at the overflow count, not shared, loses a reference.
static void plainOverflowDrop(Idris2_Value *v) {
  idris2_spinLock(&overflowLock);
  if (!overflowRemove(v))
    v->header.refCounter = IDRIS2_VP_REFCOUNTER_OVERFLOW - 1;
  idris2_spinUnlock(&overflowLock);
}

void idris2_removeReferenceSlow(Idris2_Value *v) {
  if (v->header.refCounter == IDRIS2_VP_REFCOUNTER_MAX) {
    IDRIS2_STAT(drop[IDRIS2_RC_IMMORTAL]);
    return;
  }
  if (idris2_isShared(v)) {
    IDRIS2_STAT(drop[IDRIS2_RC_SHARED]);
    if (sharedDropReference(v))
      idris2_releaseValue(v);
    return;
  }
  IDRIS2_STAT(drop[IDRIS2_RC_PLAIN]);
  plainOverflowDrop(v);
}

void idris2_markShared(Idris2_Value *root) {
  // A stack of the values to visit, rather than recursion: lists are long.
  Idris2_Value *small[64];
  Idris2_Value **stack = small;
  size_t capacity = 64, n = 0;
#define IDRIS2_PUSH(x)                                                         \
  do {                                                                         \
    Idris2_Value *x_ = (x);                                                    \
    if (!x_ || idris2_vp_is_unboxed(x_) ||                                     \
        (x_->header.reserved & (IDRIS2_STATIC_FLAG | IDRIS2_SHARED_FLAG)))     \
      break;                                                                   \
    if (n == capacity) {                                                       \
      Idris2_Value **bigger = malloc(2 * capacity * sizeof(Idris2_Value *));   \
      IDRIS2_REFC_VERIFY(bigger, "malloc failed");                             \
      memcpy(bigger, stack, n * sizeof(Idris2_Value *));                       \
      if (stack != small)                                                      \
        free(stack);                                                           \
      stack = bigger;                                                          \
      capacity *= 2;                                                           \
    }                                                                          \
    stack[n++] = x_;                                                           \
  } while (0)

  IDRIS2_PUSH(root);
  while (n > 0) {
    Idris2_Value *v = stack[--n];
    if (v->header.reserved & IDRIS2_SHARED_FLAG)
      continue; // (pushed twice)
    v->header.reserved |= IDRIS2_SHARED_FLAG;
    switch (v->header.tag) {
    case CONSTRUCTOR_TAG: {
      Idris2_Constructor *c = (Idris2_Constructor *)v;
      for (int i = 0; i < c->total; i++)
        IDRIS2_PUSH(c->args[i]);
      break;
    }
    case CLOSURE_TAG: {
      Idris2_Closure *c = (Idris2_Closure *)v;
      for (int i = 0; i < c->filled; i++)
        IDRIS2_PUSH(c->args[i]);
      break;
    }
    case IOREF_TAG:
      IDRIS2_PUSH(((Idris2_IORef *)v)->v);
      break;
    case ARRAY_TAG: {
      Idris2_Array *a = (Idris2_Array *)v;
      for (int i = 0; i < a->capacity; i++)
        IDRIS2_PUSH(a->arr[i]);
      break;
    }
    case GC_POINTER_TAG: {
      Idris2_GCPointer *p = (Idris2_GCPointer *)v;
      IDRIS2_PUSH((Idris2_Value *)p->p);
      IDRIS2_PUSH((Idris2_Value *)p->onCollectFct);
      break;
    }
    case CHANNEL_TAG: {
      Idris2_Channel *c = (Idris2_Channel *)v;
      if (c->full)
        IDRIS2_PUSH(c->value);
      break;
    }
    default:
      break;
    }
  }
#undef IDRIS2_PUSH
  if (stack != small)
    free(stack);
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
  return idris2_normaliseInteger(retVal);
}

static void idris2_mpz_set_uint64(mpz_t z, uint64_t n) {
#if ULONG_MAX >= UINT64_MAX
  mpz_set_ui(z, (unsigned long)n);
#else
  mpz_import(z, 1, 1, sizeof(n), 0, 0, &n);
#endif
}

Idris2_Value *idris2_mkIntegerFromInt64Boxed(int64_t n) {
  Idris2_Integer *retVal = idris2_mkInteger();
#if LONG_MAX >= INT64_MAX
  mpz_set_si(retVal->i, (long)n);
#else
  idris2_mpz_set_uint64(retVal->i, n < 0 ? -(uint64_t)n : (uint64_t)n);
  if (n < 0)
    mpz_neg(retVal->i, retVal->i);
#endif
  return (Idris2_Value *)retVal;
}

Idris2_Value *idris2_mkIntegerFromUInt64(uint64_t n) {
  if (n <= INT32_MAX && idris2_fitsSmallInteger((int64_t)n))
    return idris2_mkSmallInteger(n);
  Idris2_Integer *retVal = idris2_mkInteger();
  idris2_mpz_set_uint64(retVal->i, n);
  return (Idris2_Value *)retVal;
}

Idris2_Value *idris2_normaliseInteger(Idris2_Integer *i) {
  if (idris2_vp_int_shift == 32 && mpz_size(i->i) <= 1 &&
      mpz_cmp_si(i->i, INT32_MIN) >= 0 && mpz_cmp_si(i->i, INT32_MAX) <= 0) {
    int64_t n = mpz_get_si(i->i);
    mpz_clear(i->i);
    idris2_freeValue((Idris2_Value *)i);
    return idris2_mkSmallInteger(n);
  }
  return (Idris2_Value *)i;
}

Idris2_String *idris2_mkEmptyString(size_t l) {
  if (l <= 1)
    return (Idris2_String *)&idris2_predefined_nullstring;

  Idris2_String *retVal =
      (Idris2_String *)idris2_newValue(sizeof(Idris2_String) + l);
  retVal->header.tag = STRING_TAG;
  retVal->len = l - 1;
  retVal->str[l - 1] = '\0';
  return retVal;
}

Idris2_String *idris2_mkStringN(char const *s, size_t l) {
  Idris2_String *retVal = idris2_mkEmptyString(l + 1);
  if (l > 0)
    memcpy(retVal->str, s, l);
  return retVal;
}

Idris2_String *idris2_mkStringOwned(char *s) {
  Idris2_String *retVal = idris2_mkStringN(s, strlen(s));
  free(s);
  return retVal;
}

Idris2_String *idris2_mkString(char *s) {
  return idris2_mkStringN(s, strlen(s));
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
  a->lock = 0;
  a->capacity = length;
  a->arr = (Idris2_Value **)malloc(sizeof(Idris2_Value *) * length);
  memset(a->arr, 0, sizeof(Idris2_Value *) * length);
  return a;
}

// The release of values (see idris2_releaseValue) takes no stack, whatever
// their shape.  The last field of a constructor or a closure (the tail of a
// list) is released by looping.  A value released from another field (the
// spine of a SnocList is its first field, the left branch of a tree
// another one) is released by releaseDeep, which keeps the values that it
// has still to release on a stack of its own (in its frame, then on the
// heap when it is full) rather than calling itself: the C stack never holds
// more than these two frames.  (Only the finaliser of a GC pointer, which
// runs Idris code, may release values from frames of its own.)
typedef struct {
  Idris2_Value **items;
  size_t n, capacity;
  Idris2_Value **small;
} ReleaseStack;

#if defined(__GNUC__)
__attribute__((noinline, cold))
#endif
static void releasePushSlow(ReleaseStack *st, Idris2_Value *v) {
  size_t capacity = 2 * st->capacity;
  Idris2_Value **bigger = malloc(capacity * sizeof(Idris2_Value *));
  IDRIS2_REFC_VERIFY(bigger, "malloc failed");
  memcpy(bigger, st->items, st->n * sizeof(Idris2_Value *));
  if (st->items != st->small)
    free(st->items);
  st->items = bigger;
  st->capacity = capacity;
  st->items[st->n++] = v;
}

// Drop a reference that a value being released holds: 1 when it was the
// last one, and the value has to be released too.
IDRIS2_INLINE int dropField(Idris2_Value *v) {
  if (!v || idris2_vp_is_unboxed(v)) {
    IDRIS2_STAT(drop[IDRIS2_RC_IMMEDIATE]);
    return 0;
  }
  if (__builtin_expect(idris2_isPlainCounted(idris2_headerWord(v)), 1)) {
    IDRIS2_STAT(drop[IDRIS2_RC_PLAIN]);
    uint16_t count = idris2_wordRefCounter(idris2_headerWord(v));
    if (count != 1) {
      v->header.refCounter = count - 1;
      return 0;
    }
    return 1;
  }
  if (v->header.refCounter == IDRIS2_VP_REFCOUNTER_MAX) {
    IDRIS2_STAT(drop[IDRIS2_RC_IMMORTAL]);
    return 0;
  }
  if (idris2_isShared(v)) {
    IDRIS2_STAT(drop[IDRIS2_RC_SHARED]);
    return sharedDropReference(v);
  }
  // overflowed (see IDRIS2_VP_REFCOUNTER_OVERFLOW): not the last reference
  IDRIS2_STAT(drop[IDRIS2_RC_PLAIN]);
  plainOverflowDrop(v);
  return 0;
}

#if defined(__GNUC__)
__attribute__((noinline))
#endif
static void releaseDeep(Idris2_Value *elem);

// Release the fields of `elem` and free it.  Gives back its last field when
// that was its last reference (to be released next), NULL otherwise.  The
// other fields that have to be released go on the stack `st`, or to
// releaseDeep when there is none.
IDRIS2_INLINE Idris2_Value *releaseOne(Idris2_Value *elem, ReleaseStack *st) {
#define RELEASE_FIELD(x)                                                       \
  do {                                                                         \
    Idris2_Value *x_ = (x);                                                    \
    if (dropField(x_)) {                                                       \
      if (!st)                                                                 \
        releaseDeep(x_);                                                       \
      else if (__builtin_expect(st->n == st->capacity, 0))                     \
        releasePushSlow(st, x_);                                               \
      else                                                                     \
        st->items[st->n++] = x_;                                               \
    }                                                                          \
  } while (0)
  Idris2_Value *last = NULL;
  switch (elem->header.tag) {
  case INTEGER_TAG:
    mpz_clear(((Idris2_Integer *)elem)->i);
    break;

  case CLOSURE_TAG: {
    Idris2_Closure *cl = (Idris2_Closure *)elem;
    if (cl->filled > 0) {
      for (int i = 0; i < cl->filled - 1; ++i)
        RELEASE_FIELD(cl->args[i]);
      last = cl->args[cl->filled - 1];
    }
    break;
  }

  case CONSTRUCTOR_TAG: {
    Idris2_Constructor *constr = (Idris2_Constructor *)elem;
    if (constr->total > 0) {
      for (int i = 0; i < constr->total - 1; i++)
        RELEASE_FIELD(constr->args[i]);
      last = constr->args[constr->total - 1];
    }
    break;
  }
  case IOREF_TAG:
    last = ((Idris2_IORef *)elem)->v;
    break;

  case BUFFER_TAG: {
    Idris2_Buffer *b = (Idris2_Buffer *)elem;
    free(b->buffer);
    break;
  }

  case ARRAY_TAG: {
    Idris2_Array *a = (Idris2_Array *)elem;
    for (int i = 0; i < a->capacity; i++)
      RELEASE_FIELD(a->arr[i]);
    free(a->arr);
    break;
  }

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
      last = channel->value;
    break;
  }

  // Nothing to release: BITS32_TAG, BITS64_TAG, INT32_TAG, INT64_TAG,
  // DOUBLE_TAG, STRING_TAG (the bytes are part of the value), POINTER_TAG,
  // THREAD_ID_TAG (the thread clears the handle when it finishes, and it
  // holds a reference to the handle until then).
  default:
    break;
  }
#undef RELEASE_FIELD
  idris2_freeValue(elem);
  return last && dropField(last) ? last : NULL;
}

// (The stack never overflows its array, which a stack protector would check
// at every call.)
#if defined(__has_attribute)
#if __has_attribute(no_stack_protector)
__attribute__((no_stack_protector))
#endif
#endif
static void releaseDeep(Idris2_Value *elem) {
  Idris2_Value *small[16];
  ReleaseStack st = {small, 0, 16, small};
  for (;;) {
    elem = releaseOne(elem, &st);
    if (!elem) {
      if (st.n == 0)
        break;
      elem = st.items[--st.n];
    }
  }
  if (st.items != small)
    free(st.items);
}

// The last reference to `elem` is gone: release what it refers to, and free
// it.  The common cases of idris2_removeReference are inlined (see
// memoryManagement.h).
void idris2_releaseValue(Idris2_Value *elem) {
#ifdef IDRIS2_REFC_STATS
  // (the nesting of the releases: the finalisers of GC pointers)
  Idris2_Stats *stats = &idris2_worker()->stats;
  if (++stats->releaseDepth > stats->maxReleaseDepth)
    stats->maxReleaseDepth = stats->releaseDepth;
#endif
  do
    elem = releaseOne(elem, NULL);
  while (elem);
#ifdef IDRIS2_REFC_STATS
  // (the finaliser of a GC pointer may have switched workers)
  --idris2_worker()->stats.releaseDepth;
#endif
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

// The nullary constructors (with a tag) of the generated code, see
// idris2_nullaryConstructor.
#define IDRIS2_NULLARY_1(n) {IDRIS2_STOCKVAL(CONSTRUCTOR_TAG), 0, (n)}
#define IDRIS2_NULLARY_4(n)                                                    \
  IDRIS2_NULLARY_1(n), IDRIS2_NULLARY_1(n + 1), IDRIS2_NULLARY_1(n + 2),       \
      IDRIS2_NULLARY_1(n + 3)
#define IDRIS2_NULLARY_16(n)                                                   \
  IDRIS2_NULLARY_4(n), IDRIS2_NULLARY_4(n + 4), IDRIS2_NULLARY_4(n + 8),       \
      IDRIS2_NULLARY_4(n + 12)
#define IDRIS2_NULLARY_64(n)                                                   \
  IDRIS2_NULLARY_16(n), IDRIS2_NULLARY_16(n + 16), IDRIS2_NULLARY_16(n + 32),  \
      IDRIS2_NULLARY_16(n + 48)
Idris2_NullaryConstructor const
    idris2_predefined_nullary[IDRIS2_PREDEFINED_NULLARY] = {
        IDRIS2_NULLARY_64(0), IDRIS2_NULLARY_64(64), IDRIS2_NULLARY_64(128),
        IDRIS2_NULLARY_64(192)};

Idris2_ShortString const idris2_predefined_nullstring = {
    IDRIS2_STOCKVAL(STRING_TAG), 0, ""};

static bool idris2_predefined_integer_initialized = false;
Idris2_Integer idris2_predefined_Integer[100];

Idris2_Value *idris2_makeIntegerConstant(Idris2_Value **slot,
                                         char const *digits) {
  Idris2_Integer *value = idris2_mkInteger();
  mpz_set_str(value->i, digits, 10);
  Idris2_Value *v = idris2_normaliseInteger(value);
  if (!idris2_vp_is_unboxed(v))
    v->header.refCounter = IDRIS2_VP_REFCOUNTER_MAX;
  // Another thread may have made it at the same time: keep the first one.
  Idris2_Value *first = NULL;
  if (!__atomic_compare_exchange_n(slot, &first, v, 0, __ATOMIC_ACQ_REL,
                                   __ATOMIC_ACQUIRE)) {
    if (!idris2_vp_is_unboxed(v)) {
      mpz_clear(((Idris2_Integer *)v)->i);
      idris2_freeValue(v);
    }
    return first;
  }
  return v;
}

Idris2_Value *idris2_getPredefinedInteger(int n) {
  IDRIS2_REFC_VERIFY(n >= 0 && n < 100,
                     "invalid range of predefined integers.");
  if (idris2_fitsSmallInteger(n))
    return idris2_mkSmallInteger(n);

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

// ---------------------------------------------------------------------------
// Reports at exit (see idris2_reportAtExit in memoryManagement.h)
// ---------------------------------------------------------------------------

static const char *kindName(uint8_t tag) {
  switch (tag) {
  case NO_TAG:
    return "untagged";
  case BITS32_TAG:
    return "Bits32";
  case BITS64_TAG:
    return "Bits64";
  case INT32_TAG:
    return "Int32";
  case INT64_TAG:
    return "Int64";
  case INTEGER_TAG:
    return "Integer";
  case DOUBLE_TAG:
    return "Double";
  case STRING_TAG:
    return "String";
  case CLOSURE_TAG:
    return "closure";
  case CONSTRUCTOR_TAG:
    return "constructor";
  case IOREF_TAG:
    return "IORef";
  case ARRAY_TAG:
    return "array";
  case POINTER_TAG:
    return "Ptr";
  case GC_POINTER_TAG:
    return "GCPtr";
  case BUFFER_TAG:
    return "Buffer";
  case MUTEX_TAG:
    return "mutex";
  case CONDITION_TAG:
    return "condition";
  case SEMAPHORE_TAG:
    return "semaphore";
  case BARRIER_TAG:
    return "barrier";
  case CHANNEL_TAG:
    return "channel";
  case THREAD_ID_TAG:
    return "ThreadID";
  default:
    return "?";
  }
}

static int envLevel(const char *var) {
  const char *v = getenv(var);
  if (!v || !*v)
    return 0;
  return atoi(v) > 0 ? atoi(v) : (strcmp(v, "0") != 0);
}

// The live values of the pages, by class (index 0: all of them), and the
// pages by class.  Calls `visit` on every live value of the pages when it is
// not NULL.
typedef struct {
  uint64_t pages[IDRIS2_ALLOC_CLASSES + 1];
  uint64_t live[IDRIS2_ALLOC_CLASSES + 1];
  uint64_t nPages, empty, decommitted;
} PageCensus;

static void pageCensus(PageCensus *census, void (*visit)(Idris2_Value *, void *),
                       void *data) {
  memset(census, 0, sizeof(*census));
  idris2_spinLock(&allPagesLock);
  Idris2_Page *pages = allPages;
  idris2_spinUnlock(&allPagesLock);
  for (Idris2_Page *page = pages; page; page = page->nextPage) {
    unsigned cls = page->cls;
    census->nPages++;
    if (cls == 0) {
      // empty
      if (page->decommitted)
        census->decommitted++;
      else
        census->empty++;
      continue;
    }
    size_t size = (size_t)cls * IDRIS2_ALLOC_UNIT;
    char *start = (char *)page + ((sizeof(Idris2_Page) + 15) & ~(size_t)15);
    size_t used = (size_t)(page->bump - start) / size;
    // A bit per value of the page: 1 when it is free.
    uint8_t freeSlots[IDRIS2_PAGE_SIZE / IDRIS2_ALLOC_UNIT / 8];
    memset(freeSlots, 0, (used + 7) / 8);
    size_t nFree = 0;
    for (Idris2_FreeValue *v = page->free; v; v = v->next) {
      size_t i = (size_t)((char *)v - start) / size;
      if ((char *)v < start || i >= used ||
          (char *)v != start + i * size || (freeSlots[i / 8] >> (i % 8)) & 1) {
        fprintf(stderr, "RefC: the free list of the page %p is broken\n",
                (void *)page);
        break;
      }
      freeSlots[i / 8] |= (uint8_t)(1u << (i % 8));
      nFree++;
    }
    census->pages[cls]++;
    census->live[cls] += used - nFree;
    census->live[0] += used - nFree;
    if (visit)
      for (size_t i = 0; i < used; i++)
        if (!((freeSlots[i / 8] >> (i % 8)) & 1))
          visit((Idris2_Value *)(start + i * size), data);
  }
}

// Put back the values that other workers freed, so that they do not count
// as live.  Only when no other thread runs.
static void collectAllRemoteFrees(void) {
  int n = idris2_workerCount();
  for (int i = 0; i < n; i++)
    collectRemoteFrees(idris2_workerAt(i));
}

void idris2_dumpMemoryStats(void) {
  int nWorkers = idris2_workerCount();
  PageCensus census;
  pageCensus(&census, NULL, NULL);
  fprintf(stderr, "RefC memory statistics (%d worker%s)\n", nWorkers,
          nWorkers == 1 ? "" : "s");
  fprintf(stderr,
          "  pages: %llu (%.1f MiB), %llu empty, %llu gave their memory back; "
          "%lld pages in use at the peak\n",
          (unsigned long long)census.nPages,
          (double)census.nPages * IDRIS2_PAGE_SIZE / (1024.0 * 1024.0),
          (unsigned long long)census.empty,
          (unsigned long long)census.decommitted,
          (long long)__atomic_load_n(&peakPagesInUse, __ATOMIC_RELAXED));
  Idris2_Stats sum;
  memset(&sum, 0, sizeof(sum));
  for (int i = 0; i < nWorkers; i++) {
    Idris2_Stats *st = &idris2_workerAt(i)->stats;
    for (int c = 0; c <= IDRIS2_ALLOC_CLASSES; c++) {
      sum.allocs[c] += st->allocs[c];
      sum.frees[c] += st->frees[c];
    }
    sum.largeAllocs += st->largeAllocs;
    sum.largeFrees += st->largeFrees;
    sum.pagesCreated += st->pagesCreated;
    sum.pagesEmptied += st->pagesEmptied;
    sum.pagesReused += st->pagesReused;
    sum.pagesDecommitted += st->pagesDecommitted;
    sum.pagesToPool += st->pagesToPool;
    sum.remoteFreesReceived += st->remoteFreesReceived;
    sum.overflows += st->overflows;
    for (int k = 0; k < IDRIS2_RC_KINDS; k++) {
      sum.dup[k] += st->dup[k];
      sum.drop[k] += st->drop[k];
    }
    sum.uniqueHit += st->uniqueHit;
    sum.uniqueMiss += st->uniqueMiss;
    sum.reuseHit += st->reuseHit;
    sum.reuseMiss += st->reuseMiss;
    for (int k = 0; k < IDRIS2_APPLY_KINDS; k++)
      sum.apply[k] += st->apply[k];
    if (st->maxReleaseDepth > sum.maxReleaseDepth)
      sum.maxReleaseDepth = st->maxReleaseDepth;
  }
#ifdef IDRIS2_REFC_STATS
  int stats = 1;
#else
  int stats = 0;
#endif
  fprintf(stderr, "  %5s %6s %7s %12s%s\n", "class", "bytes", "pages", "live",
          stats ? "       allocated        freed" : "");
  for (int c = 1; c <= IDRIS2_ALLOC_CLASSES; c++) {
    if (!census.pages[c] && !sum.allocs[c])
      continue;
    fprintf(stderr, "  %5d %6d %7llu %12llu", c, c * IDRIS2_ALLOC_UNIT,
            (unsigned long long)census.pages[c],
            (unsigned long long)census.live[c]);
    if (stats)
      fprintf(stderr, " %15llu %12llu", (unsigned long long)sum.allocs[c],
              (unsigned long long)sum.frees[c]);
    fprintf(stderr, "\n");
  }
  fprintf(stderr, "  large values (malloc): %lld live\n",
          (long long)__atomic_load_n(&largeLive, __ATOMIC_RELAXED));
  if (!stats) {
    fprintf(stderr, "  (build with -DIDRIS2_REFC_STATS for the counters)\n");
    return;
  }
  uint64_t allocs = sum.largeAllocs;
  for (int c = 1; c <= IDRIS2_ALLOC_CLASSES; c++)
    allocs += sum.allocs[c];
  uint64_t dups = 0, drops = 0;
  for (int k = 0; k < IDRIS2_RC_KINDS; k++) {
    dups += sum.dup[k];
    drops += sum.drop[k];
  }
  fprintf(stderr, "  allocations: %llu (%llu large, %llu freed)\n",
          (unsigned long long)allocs, (unsigned long long)sum.largeAllocs,
          (unsigned long long)sum.largeFrees);
  fprintf(stderr,
          "  pages: %llu created, %llu emptied, %llu reused, %llu gave their "
          "memory back, %llu times given to the pool by idle workers; remote frees "
          "received: %llu\n",
          (unsigned long long)sum.pagesCreated,
          (unsigned long long)sum.pagesEmptied,
          (unsigned long long)sum.pagesReused,
          (unsigned long long)sum.pagesDecommitted,
          (unsigned long long)sum.pagesToPool,
          (unsigned long long)sum.remoteFreesReceived);
  static const char *const rcKinds[IDRIS2_RC_KINDS] = {"immediate", "plain",
                                                        "shared", "immortal"};
  fprintf(stderr, "  %-8s %15s", "", "total");
  for (int k = 0; k < IDRIS2_RC_KINDS; k++)
    fprintf(stderr, " %15s", rcKinds[k]);
  fprintf(stderr, "\n  %-8s %15llu", "dup", (unsigned long long)dups);
  for (int k = 0; k < IDRIS2_RC_KINDS; k++)
    fprintf(stderr, " %15llu", (unsigned long long)sum.dup[k]);
  fprintf(stderr, "\n  %-8s %15llu", "drop", (unsigned long long)drops);
  for (int k = 0; k < IDRIS2_RC_KINDS; k++)
    fprintf(stderr, " %15llu", (unsigned long long)sum.drop[k]);
  fprintf(stderr, "\n");
  fprintf(stderr, "  count operations per allocation: %.2f\n",
          allocs ? (double)(dups + drops) / (double)allocs : 0.0);
  fprintf(stderr, "  counts that overflowed into the side table: %llu\n",
          (unsigned long long)sum.overflows);
  fprintf(stderr, "  uniqueness tests: %llu unique, %llu not\n",
          (unsigned long long)sum.uniqueHit,
          (unsigned long long)sum.uniqueMiss);
  fprintf(stderr, "  reuse: %llu cells reused, %llu not unique\n",
          (unsigned long long)sum.reuseHit, (unsigned long long)sum.reuseMiss);
  fprintf(stderr,
          "  closure applications: %llu in place, %llu saturated unique, "
          "%llu saturated copied, %llu under-saturated copies, %llu shared\n",
          (unsigned long long)sum.apply[IDRIS2_APPLY_IN_PLACE],
          (unsigned long long)sum.apply[IDRIS2_APPLY_SATURATED],
          (unsigned long long)sum.apply[IDRIS2_APPLY_COPIED],
          (unsigned long long)sum.apply[IDRIS2_APPLY_UNDER_COPY],
          (unsigned long long)sum.apply[IDRIS2_APPLY_SHARED]);
  fprintf(stderr, "  deepest release nesting: %u\n", sum.maxReleaseDepth);
}

// The live values of the leak check.
#define LEAK_SAMPLES 20
typedef struct {
  Idris2_Value **values;
  size_t n, capacity;
} ValueList;

static void collectValue(Idris2_Value *v, void *data) {
  ValueList *list = data;
  if (list->n == list->capacity) {
    size_t capacity = list->capacity ? 2 * list->capacity : 4096;
    Idris2_Value **bigger =
        realloc(list->values, capacity * sizeof(Idris2_Value *));
    if (!bigger)
      return; // (the counts will be a bit off)
    list->values = bigger;
    list->capacity = capacity;
  }
  list->values[list->n++] = v;
}

static int compareAddresses(const void *a, const void *b) {
  uintptr_t x = (uintptr_t)*(Idris2_Value *const *)a;
  uintptr_t y = (uintptr_t)*(Idris2_Value *const *)b;
  return x < y ? -1 : x > y;
}

// The index of `v` in the sorted list, or -1 when it is not a live value of
// the pages (a static value, or one from malloc, say).
static ptrdiff_t findValue(ValueList *list, Idris2_Value *v) {
  size_t lo = 0, hi = list->n;
  while (lo < hi) {
    size_t mid = lo + (hi - lo) / 2;
    if ((uintptr_t)list->values[mid] < (uintptr_t)v)
      lo = mid + 1;
    else
      hi = mid;
  }
  return lo < list->n && list->values[lo] == v ? (ptrdiff_t)lo : -1;
}

static void describeValue(Idris2_Value *v) {
  fprintf(stderr, "    %p %s", (void *)v, kindName(v->header.tag));
  if (v->header.tag == CONSTRUCTOR_TAG) {
    Idris2_Constructor *c = (Idris2_Constructor *)v;
    if (c->tag >= 0)
      fprintf(stderr, " tag %d", c->tag);
    else
      fprintf(stderr, " %s", (const char *)c->args[c->total]);
    fprintf(stderr, " (%d field%s)", c->total, c->total == 1 ? "" : "s");
  } else if (v->header.tag == STRING_TAG) {
    Idris2_String *s = (Idris2_String *)v;
    fprintf(stderr, " \"%.40s\"%s", s->str, s->len > 40 ? "..." : "");
  } else if (v->header.tag == CLOSURE_TAG) {
    Idris2_Closure *c = (Idris2_Closure *)v;
    fprintf(stderr, " %d of %d arguments", c->filled, c->arity);
  }
  if (v->header.refCounter == IDRIS2_VP_REFCOUNTER_MAX)
    fprintf(stderr, ", immortal\n");
  else
    fprintf(stderr, ", %u reference%s\n", v->header.refCounter,
            v->header.refCounter == 1 ? "" : "s");
}

static void printKinds(const char *what, uint64_t *byTag) {
  fprintf(stderr, "  %s:", what);
  for (int t = 0; t < 256; t++)
    if (byTag[t])
      fprintf(stderr, " %s %llu", kindName((uint8_t)t),
              (unsigned long long)byTag[t]);
  fprintf(stderr, "\n");
}

// Mark what the immortal values (the constants) refer to: only the root of
// a constant is made immortal, its fields keep their counts.
static void markFromConstants(ValueList *list, uint8_t *reached) {
  size_t n = 0, capacity = 1024;
  Idris2_Value **stack = malloc(capacity * sizeof(Idris2_Value *));
  if (!stack)
    return;
#define LEAK_PUSH(x)                                                           \
  do {                                                                         \
    Idris2_Value *x_ = (Idris2_Value *)(x);                                    \
    if (!x_ || idris2_vp_is_unboxed(x_))                                       \
      break;                                                                   \
    ptrdiff_t i_ = findValue(list, x_);                                        \
    if (i_ < 0 || reached[i_])                                                 \
      break;                                                                   \
    reached[i_] = 1;                                                           \
    if (n == capacity) {                                                       \
      Idris2_Value **bigger =                                                  \
          realloc(stack, 2 * capacity * sizeof(Idris2_Value *));               \
      if (!bigger)                                                             \
        goto out;                                                              \
      stack = bigger;                                                          \
      capacity *= 2;                                                           \
    }                                                                          \
    stack[n++] = x_;                                                           \
  } while (0)
  for (size_t i = 0; i < list->n; i++)
    if (list->values[i]->header.refCounter == IDRIS2_VP_REFCOUNTER_MAX)
      LEAK_PUSH(list->values[i]);
  while (n > 0) {
    Idris2_Value *v = stack[--n];
    switch (v->header.tag) {
    case CONSTRUCTOR_TAG: {
      Idris2_Constructor *c = (Idris2_Constructor *)v;
      for (int i = 0; i < c->total; i++)
        LEAK_PUSH(c->args[i]);
      break;
    }
    case CLOSURE_TAG: {
      Idris2_Closure *c = (Idris2_Closure *)v;
      for (int i = 0; i < c->filled; i++)
        LEAK_PUSH(c->args[i]);
      break;
    }
    case IOREF_TAG:
      LEAK_PUSH(((Idris2_IORef *)v)->v);
      break;
    case ARRAY_TAG: {
      Idris2_Array *a = (Idris2_Array *)v;
      for (int i = 0; i < a->capacity; i++)
        LEAK_PUSH(a->arr[i]);
      break;
    }
    case GC_POINTER_TAG:
      LEAK_PUSH(((Idris2_GCPointer *)v)->p);
      LEAK_PUSH(((Idris2_GCPointer *)v)->onCollectFct);
      break;
    case CHANNEL_TAG:
      if (((Idris2_Channel *)v)->full)
        LEAK_PUSH(((Idris2_Channel *)v)->value);
      break;
    default:
      break;
    }
  }
#undef LEAK_PUSH
out:
  free(stack);
}

static void leakCheck(int level, long long threadsLeft) {
  if (threadsLeft > 0) {
    fprintf(stderr,
            "RefC leak check: skipped, %lld thread%s still running (their "
            "values would be counted as leaks)\n",
            threadsLeft, threadsLeft == 1 ? " is" : "s are");
    return;
  }
  ValueList list = {NULL, 0, 0};
  PageCensus pages;
  pageCensus(&pages, collectValue, &list);
  if (list.n > 0)
    qsort(list.values, list.n, sizeof(Idris2_Value *), compareAddresses);
  uint8_t *reached = calloc(list.n + 1, 1);
  uint64_t *byTag = calloc(3 * 256, sizeof(uint64_t));
  if (!reached || !byTag) {
    free(list.values);
    free(reached);
    free(byTag);
    return;
  }
  markFromConstants(&list, reached);
  uint64_t *leaked = byTag, *held = byTag + 256, *immortal = byTag + 512;
  uint64_t nLeaked = 0, nHeld = 0, nImmortal = 0;
  for (size_t i = 0; i < list.n; i++) {
    Idris2_Value *v = list.values[i];
    if (v->header.refCounter == IDRIS2_VP_REFCOUNTER_MAX) {
      immortal[v->header.tag]++;
      nImmortal++;
    } else if (reached[i]) {
      held[v->header.tag]++;
      nHeld++;
    } else {
      leaked[v->header.tag]++;
      nLeaked++;
    }
  }
  long long large = (long long)__atomic_load_n(&largeLive, __ATOMIC_RELAXED);
  fprintf(stderr,
          "RefC leak check: %llu leaked values, %llu constants and %llu "
          "values that they hold; %lld large values (from malloc, not looked "
          "at)\n",
          (unsigned long long)nLeaked, (unsigned long long)nImmortal,
          (unsigned long long)nHeld, large);
  if (nLeaked)
    printKinds("leaked values", leaked);
  if (level >= 2) {
    if (nImmortal)
      printKinds("constants", immortal);
    if (nHeld)
      printKinds("held by constants", held);
    int samples = 0;
    for (size_t i = 0; i < list.n && samples < LEAK_SAMPLES; i++) {
      Idris2_Value *v = list.values[i];
      if (reached[i] || v->header.refCounter == IDRIS2_VP_REFCOUNTER_MAX)
        continue;
      if (samples++ == 0)
        fprintf(stderr, "  some leaked values:\n");
      describeValue(v);
    }
  } else if (nLeaked) {
    fprintf(stderr, "  (IDRIS2_REFC_LEAKCHECK=2 shows some of them)\n");
  }
  free(list.values);
  free(reached);
  free(byTag);
}

void idris2_reportAtExit(int finished, long long threadsLeft) {
  static int done = 0;
  if (done)
    return;
  done = 1;
  int memstats = envLevel("IDRIS2_REFC_MEMSTATS");
  int leaks = envLevel("IDRIS2_REFC_LEAKCHECK");
  if (!memstats && !leaks)
    return;
  // The values freed by other workers are put back first, when nothing else
  // can touch the pages: no thread runs, and the idle workers stop giving
  // their pages to the pool.
  idris2_spinLock(&releaseLock);
  exiting = 1;
  idris2_spinUnlock(&releaseLock);
  if (finished && threadsLeft == 0)
    collectAllRemoteFrees();
  if (memstats)
    idris2_dumpMemoryStats();
  if (leaks) {
    if (finished)
      leakCheck(leaks, threadsLeft);
    else
      fprintf(stderr, "RefC leak check: skipped, the program exits before "
                      "its main expression is done\n");
  }
}
