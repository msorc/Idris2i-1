// The cells of stage A of the flat layout (docs/source/backends/refc-flat-layout.rst),
// against the runtime alone: a constructor cell whose `total` counts only its
// pointer fields, followed by raw bytes.  The raw bytes are made to look like
// pointers to live values, so that a runtime path that read them as fields
// (the release walk, the marking of shared values, the leak walk) would
// change the counts or the flags of those values, or crash.
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "runtime.h"
#include "threads.h"

// What the code generator would declare for `MkR : String -> Double -> Int -> R`
// (one pointer field, two raw fields).
typedef struct {
  Idris2i_1_header header;
  uint16_t total;
  int16_t tag;
  Idris2i_1_Value *args[1];
  double d;
  int64_t i;
} Raw_MkR;

// With more pointer fields than fit in a pool cell: from idris2i_1_allocLarge.
#define BIG 80
typedef struct {
  Idris2i_1_header header;
  uint16_t total;
  int16_t tag;
  Idris2i_1_Value *args[BIG];
  double d;
  int64_t i;
} Raw_Big;

static Idris2i_1_Value *newRaw(size_t size, int np) {
  Idris2i_1_Constructor *c = (Idris2i_1_Constructor *)idris2i_1_newValue(size);
  c->header.tag = CONSTRUCTOR_TAG;
  c->total = (uint16_t)np;
  c->tag = 0;
  return (Idris2i_1_Value *)c;
}

// The alignment that the ABI gives a double in a struct (4 on 32 bit x86, 8
// on most others): a raw field must be at least that aligned.
#define DOUBLE_ALIGN offsetof(struct { char c; double d; }, d)

static int failures = 0;
#define CHECK(cond, what)                                                      \
  do {                                                                         \
    if (!(cond)) {                                                             \
      printf("FAIL: %s\n", what);                                              \
      failures++;                                                              \
    }                                                                          \
  } while (0)

// A static cell with raw fields, as a constant of the program would be.
static const struct {
  Idris2i_1_header header;
  uint16_t total;
  int16_t tag;
  double d;
  int64_t i;
} staticR = {IDRIS2I_1_STOCKVAL(CONSTRUCTOR_TAG), 0, 0, 2.5, (int64_t)0x7ffffffffffffff0};

static Idris2i_1_Value *run(void) {
  // A live value whose address the raw fields hold.
  Idris2i_1_Value *decoy = (Idris2i_1_Value *)idris2i_1_mkString("decoy");
  Idris2i_1_Value *field = (Idris2i_1_Value *)idris2i_1_mkString("field");

  // Release: only the pointer field is released; the decoy is not touched.
  Raw_MkR *r = (Raw_MkR *)newRaw(sizeof(Raw_MkR), 1);
  r->args[0] = field;
  memcpy(&r->d, &decoy, sizeof(decoy) < sizeof(double) ? sizeof(decoy) : sizeof(double));
  r->i = (int64_t)(intptr_t)decoy;
  CHECK(((uintptr_t)&r->d % DOUBLE_ALIGN) == 0, "raw double aligned in a pool cell");
  idris2i_1_newReference(field);
  idris2i_1_removeReference((Idris2i_1_Value *)r);
  CHECK(field->header.refCounter == 1, "the pointer field is released");
  CHECK(decoy->header.refCounter == 1, "the raw fields are not released");

  // Marking a cell shared: its pointer field is shared, the decoy is not.
  r = (Raw_MkR *)newRaw(sizeof(Raw_MkR), 1);
  r->args[0] = field;
  r->i = (int64_t)(intptr_t)decoy;
  memcpy(&r->d, &decoy, sizeof(decoy) < sizeof(double) ? sizeof(decoy) : sizeof(double));
  idris2i_1_markShared((Idris2i_1_Value *)r);
  CHECK(idris2i_1_isShared((Idris2i_1_Value *)r), "the cell is shared");
  CHECK(idris2i_1_isShared(field), "its pointer field is shared");
  CHECK(!idris2i_1_isShared(decoy), "what its raw fields point to is not");
  idris2i_1_removeReference((Idris2i_1_Value *)r); // (frees `field` too)

  // A large cell (beyond the pools): its raw double is aligned on 8 bytes,
  // on 32 bit platforms too.
  Raw_Big *b = (Raw_Big *)newRaw(sizeof(Raw_Big), BIG);
  CHECK(b->header.reserved == 0, "a large cell is not from a pool");
  CHECK(((uintptr_t)b & 7) == 0, "a large cell is aligned on 8 bytes");
  CHECK(((uintptr_t)&b->d % DOUBLE_ALIGN) == 0, "raw double aligned in a large cell");
  for (int k = 0; k < BIG; k++)
    b->args[k] = idris2i_1_newReference(decoy);
  b->d = 1.5;
  b->i = (int64_t)(intptr_t)decoy;
  idris2i_1_removeReference((Idris2i_1_Value *)b);
  CHECK(decoy->header.refCounter == 1, "a large cell releases its pointer fields only");

  // Reuse of a freed cell of the same size class by a cell of another
  // layout (as `refc-size-reuse` would do): the class is that of the size.
  Raw_MkR *r1 = (Raw_MkR *)newRaw(sizeof(Raw_MkR), 1);
  r1->args[0] = NULL;
  idris2i_1_freeValue((Idris2i_1_Value *)r1);
  Idris2i_1_Constructor *c3 = idris2i_1_newConstructor(3, 0); // 8 + 3 * 8 bytes
  int sameClass = sizeof(Raw_MkR) == sizeof(Idris2i_1_Constructor) + 3 * sizeof(Idris2i_1_Value *);
  if (sameClass)
    CHECK((void *)c3 == (void *)r1, "a cell of the same size reuses the freed one");
  c3->args[0] = c3->args[1] = c3->args[2] = NULL;
  idris2i_1_removeReference((Idris2i_1_Value *)c3);

  // A static cell with raw fields: counting does nothing, marking it shared
  // does not write it (it is in read only memory).
  Idris2i_1_Value *s = (Idris2i_1_Value *)&staticR;
  idris2i_1_newReference(s);
  idris2i_1_removeReference(s);
  idris2i_1_markShared(s);
  CHECK(staticR.header.refCounter == IDRIS2I_1_VP_REFCOUNTER_MAX, "a static cell stays immortal");

  // Kept to the end for the leak check (IDRIS2I_1_REFC_LEAKCHECK), as a
  // constant of the program (an immortal allocated value): the check follows
  // its pointer field (`held` is one value that it holds) but not its raw
  // field, which points to `loose` (reported as a leaked value).
  Idris2i_1_Value *held = (Idris2i_1_Value *)idris2i_1_mkString("held");
  Idris2i_1_Value *loose = (Idris2i_1_Value *)idris2i_1_mkString("loose");
  Raw_MkR *kept = (Raw_MkR *)newRaw(sizeof(Raw_MkR), 1);
  kept->args[0] = held;
  kept->d = 0.1;
  kept->i = (int64_t)(intptr_t)loose;
  kept->header.refCounter = IDRIS2I_1_VP_REFCOUNTER_MAX;

  idris2i_1_removeReference(decoy);
  printf("%s\n", failures == 0 ? "raw cells: ok" : "raw cells: FAILED");
  return NULL;
}

int main(void) {
  idris2i_1_threadSchedulerRun(run);
  return failures;
}
