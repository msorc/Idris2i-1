// Stage B of the RefC flat layout design (docs/source/backends/refc-flat-layout.rst):
// the C of one `mread` and one `write` of a `LinArray Particle`, as the code
// generator would emit them, with a descriptor that is a compile time
// constant at the access (FAST) or only known at run time (GENERIC: the
// descriptor drives a byte copy, and a read gives a stage A cell).
//
// Built against the RefC runtime for the cells of the generic path:
//   cc -O2 -I<support>/refc -I<support>/c access.c <support>/refc/*.c <support>/c/*.c -lgmp -lm -pthread
// Run:   ./a.out fast N | generic N     (N element updates, as in W1's sweep)
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "runtime.h"
#include "threads.h"

// The descriptor of a slot layout: `Maybe` of a record of raw fields.
typedef struct {
  uint64_t id;       // a hash of the layout, compared at the fast accesses
  uint32_t slotSize; // tag byte (padded) + payload
  uint32_t payload;  // bytes of the record's raw fields (= its cell's raw part)
  uint32_t cellSize; // size of the record's stage A cell
} FlatLayout;

// A flat array: one block.
typedef struct {
  Idris2_header header;
  uint32_t pad;
  int64_t size;
  const FlatLayout *layout;
  uint64_t layoutId;
  _Alignas(8) unsigned char slots[];
} FlatArray;

// The stage A cell of MkParticle (no pointer field).
typedef struct {
  Idris2_header header;
  uint16_t total;
  int16_t tag;
  double px, py, vx, vy;
  int64_t hits;
} Particle_cell;

// The flat value of a `Maybe Particle` (stage C: a local, a result).
typedef struct {
  uint8_t present;
  double px, py, vx, vy;
  int64_t hits;
} MaybeParticle;

static const FlatLayout layout_Maybe_MkParticle = {
    UINT64_C(0x8f3e5a17c2d94b61), 48, 40, sizeof(Particle_cell)};

static FlatArray *newFlat(const FlatLayout *l, int64_t n) {
  FlatArray *a = malloc(sizeof(FlatArray) + (size_t)n * l->slotSize);
  a->size = n;
  a->layout = l;
  a->layoutId = l->id;
  memset(a->slots, 0, (size_t)n * l->slotSize);
  return a;
}

// ---- generic path: the descriptor is only known at run time ----

// A read boxes the slot: a stage A cell for the record and a Just cell.
__attribute__((noinline)) static Idris2_Value *flatGetGeneric(FlatArray *a, int64_t i) {
  if (i < 0 || i >= a->size)
    return NULL;
  const FlatLayout *l = a->layout;
  unsigned char *slot = a->slots + (size_t)i * l->slotSize;
  if (!slot[0])
    return NULL;
  Idris2_Constructor *c = (Idris2_Constructor *)idris2_newValue(l->cellSize);
  c->header.tag = CONSTRUCTOR_TAG;
  c->total = 0;
  c->tag = 0;
  memcpy((unsigned char *)c + 8, slot + 8, l->payload);
  Idris2_Constructor *just = idris2_newConstructor(1, 1);
  just->args[0] = (Idris2_Value *)c;
  return (Idris2_Value *)just;
}

// A write unboxes the cell it is given (and drops it).
__attribute__((noinline)) static int flatSetGeneric(FlatArray *a, int64_t i, Idris2_Value *x) {
  if (i < 0 || i >= a->size) {
    idris2_removeReference(x);
    return 0;
  }
  const FlatLayout *l = a->layout;
  unsigned char *slot = a->slots + (size_t)i * l->slotSize;
  slot[0] = 1;
  memcpy(slot + 8, (unsigned char *)x + 8, l->payload);
  idris2_removeReference(x);
  return 1;
}

// ---- fast path: the descriptor is a constant at the access ----

static inline MaybeParticle flatGetParticle(FlatArray *a, int64_t i) {
  MaybeParticle r = {0};
  if (__builtin_expect(a->layoutId == layout_Maybe_MkParticle.id, 1)) {
    if (i >= 0 && i < a->size) {
      unsigned char *slot = a->slots + (size_t)i * 48;
      r.present = slot[0];
      memcpy(&r.px, slot + 8, 40);
    }
    return r;
  }
  // (not taken: the array was made by generic code)
  Idris2_Value *v = flatGetGeneric(a, i);
  if (v) {
    Particle_cell *c = (Particle_cell *)((Idris2_Constructor *)v)->args[0];
    r.present = 1;
    memcpy(&r.px, &c->px, 40);
    idris2_removeReference(v);
  }
  return r;
}

static inline int flatSetParticle(FlatArray *a, int64_t i, const MaybeParticle *p) {
  if (__builtin_expect(a->layoutId == layout_Maybe_MkParticle.id, 1)) {
    if (i < 0 || i >= a->size)
      return 0;
    unsigned char *slot = a->slots + (size_t)i * 48;
    slot[0] = 1;
    memcpy(slot + 8, &p->px, 40);
    return 1;
  }
  Particle_cell *c = (Particle_cell *)idris2_newValue(sizeof(Particle_cell));
  c->header.tag = CONSTRUCTOR_TAG;
  c->total = 0;
  c->tag = 0;
  memcpy(&c->px, &p->px, 40);
  return flatSetGeneric(a, i, (Idris2_Value *)c);
}

// W1's update of one element: read i and i+1, write i (move as in particles.idr).
static void move(MaybeParticle *out, const MaybeParticle *p, const MaybeParticle *q) {
  double vx = (p->vx + (q->px - p->px) * 0.01) * 0.999;
  double vy = (p->vy + (q->py - p->py) * 0.01 - 0.05) * 0.999;
  out->present = 1;
  out->px = p->px + vx;
  out->py = p->py + vy;
  out->vx = vx;
  out->vy = vy;
  out->hits = p->hits;
}

static int64_t n_elems = 100000;
static int fastMode;
static int64_t updates;

static Idris2_Value *run(void) {
  FlatArray *a = newFlat(&layout_Maybe_MkParticle, n_elems);
  for (int64_t i = 0; i < n_elems; i++) {
    MaybeParticle p = {1, (double)(i % 1000), (double)((i * 7) % 1000), 0, 0, 0};
    flatSetParticle(a, i, &p);
  }
  double sum = 0;
  for (int64_t k = 0; k < updates; k++) {
    int64_t i = k % n_elems;
    int64_t j = i + 1 >= n_elems ? 0 : i + 1;
    if (fastMode) {
      MaybeParticle p = flatGetParticle(a, i), q = flatGetParticle(a, j), r;
      if (p.present && q.present) {
        move(&r, &p, &q);
        flatSetParticle(a, i, &r);
      }
    } else {
      Idris2_Value *mp = flatGetGeneric(a, i), *mq = flatGetGeneric(a, j);
      if (mp && mq) {
        Particle_cell *p = (Particle_cell *)((Idris2_Constructor *)mp)->args[0];
        Particle_cell *q = (Particle_cell *)((Idris2_Constructor *)mq)->args[0];
        MaybeParticle pp = {1, p->px, p->py, p->vx, p->vy, p->hits};
        MaybeParticle qq = {1, q->px, q->py, q->vx, q->vy, q->hits};
        MaybeParticle r;
        move(&r, &pp, &qq);
        Particle_cell *c = (Particle_cell *)idris2_newValue(sizeof(Particle_cell));
        c->header.tag = CONSTRUCTOR_TAG;
        c->total = 0;
        c->tag = 0;
        memcpy(&c->px, &r.px, 40);
        flatSetGeneric(a, i, (Idris2_Value *)c);
      }
      idris2_removeReference(mp);
      idris2_removeReference(mq);
    }
  }
  for (int64_t i = 0; i < n_elems; i++) {
    MaybeParticle p = flatGetParticle(a, i);
    sum += p.px + p.py;
  }
  printf("%.3f\n", sum);
  free(a);
  return NULL;
}

int main(int argc, char **argv) {
  fastMode = argc > 1 && strcmp(argv[1], "fast") == 0;
  updates = argc > 2 ? atoll(argv[2]) : 1000000;
  idris2_threadSchedulerRun(run);
  return 0;
}
