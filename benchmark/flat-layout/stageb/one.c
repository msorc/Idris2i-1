#include <stdint.h>
#include <string.h>
typedef struct { uint64_t id; uint32_t slotSize, payload, cellSize; } FlatLayout;
typedef struct { uint32_t header, pad; int64_t size; const FlatLayout *layout; uint64_t layoutId; _Alignas(8) unsigned char slots[]; } FlatArray;
typedef struct { uint8_t present; double px, py, vx, vy; int64_t hits; } MaybeParticle;
void *flatGetGeneric(FlatArray *a, int64_t i);
int flatSetGeneric(FlatArray *a, int64_t i, const MaybeParticle *p);
// mread a i, at a site where the layout is a constant
MaybeParticle mread_fast(FlatArray *a, int64_t i) {
  MaybeParticle r = {0};
  if (__builtin_expect(a->layoutId == UINT64_C(0x8f3e5a17c2d94b61), 1)) {
    if (i >= 0 && i < a->size) {
      unsigned char *slot = a->slots + (size_t)i * 48;
      r.present = slot[0];
      memcpy(&r.px, slot + 8, 40);
    }
    return r;
  }
  flatGetGeneric(a, i);
  return r;
}
int write_fast(FlatArray *a, int64_t i, const MaybeParticle *p) {
  if (__builtin_expect(a->layoutId == UINT64_C(0x8f3e5a17c2d94b61), 1)) {
    if (i < 0 || i >= a->size) return 0;
    unsigned char *slot = a->slots + (size_t)i * 48;
    slot[0] = 1;
    memcpy(slot + 8, &p->px, 40);
    return 1;
  }
  return flatSetGeneric(a, i, p);
}
