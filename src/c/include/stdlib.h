/* Minimal libc stub: yoshida builds its C dependencies without a libc. */
#ifndef YSTB_STDLIB_H
#define YSTB_STDLIB_H
#include <stddef.h>
void *ystb_malloc(size_t size);
void *ystb_realloc(void *ptr, size_t size);
void ystb_free(void *ptr);
#define malloc ystb_malloc
#define realloc ystb_realloc
#define free ystb_free
static inline int ystb_abs(int x) { return x < 0 ? -x : x; }
#define abs(x) ystb_abs(x)
#endif
