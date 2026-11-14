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
long ystb_strtol(const char *s, char **end, int base);
long long ystb_strtoll(const char *s, char **end, int base);
void ystb_qsort(void *base, size_t n, size_t size, int (*cmp)(const void *, const void *));
#define strtol ystb_strtol
#define strtoll ystb_strtoll
#define qsort ystb_qsort
#endif
