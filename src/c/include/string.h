#ifndef YSTB_STRING_H
#define YSTB_STRING_H
#include <stddef.h>
size_t ystb_strlen(const char *s);
int ystb_strcmp(const char *a, const char *b);
int ystb_strncmp(const char *a, const char *b, size_t n);
#define memcpy(d, s, n) __builtin_memcpy(d, s, n)
#define memmove(d, s, n) __builtin_memmove(d, s, n)
#define memset(d, c, n) __builtin_memset(d, c, n)
#define memcmp(a, b, n) __builtin_memcmp(a, b, n)
#define strlen(s) ystb_strlen(s)
#define strcmp(a, b) ystb_strcmp(a, b)
#define strncmp(a, b, n) ystb_strncmp(a, b, n)
#endif
