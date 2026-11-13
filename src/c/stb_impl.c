/* Compiles the single-header C libraries for yoshida (native and wasm32). */
#define STBI_NO_STDIO
#define STBI_NO_HDR
#define STBI_NO_LINEAR
#define STBI_NO_SIMD
#define STBI_NO_THREAD_LOCALS
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_ONLY_GIF
#define STBI_ONLY_BMP
#define STBI_ASSERT(x) ((void)0)
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#define STBTT_assert(x) ((void)0)
#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

int ystb_fontinfo_size(void) { return (int)sizeof(stbtt_fontinfo); }

/* simplewebp (BSD-3-Clause, see the end of simplewebp.h): WebP decoding. */
#define SIMPLEWEBP_DISABLE_STDIO
#define SIMPLEWEBP_IMPLEMENTATION
#include "simplewebp.h"

/* nanosvg (zlib license, see nanosvg-LICENSE.txt): SVG parsing and
   rasterising, for SVG files used as images. */
#define NANOSVG_IMPLEMENTATION
#include "nanosvg.h"
#define NANOSVGRAST_IMPLEMENTATION
#include "nanosvgrast.h"

/* The libc functions nanosvg needs beyond the ones in include/, written
   for exactly the uses it has. */
#include <stdarg.h>

static int ystb_digit(char c, int base) {
	int v = -1;
	if (c >= '0' && c <= '9') v = c - '0';
	else if (c >= 'a' && c <= 'z') v = c - 'a' + 10;
	else if (c >= 'A' && c <= 'Z') v = c - 'A' + 10;
	return v >= 0 && v < base ? v : -1;
}

static int ystb_space(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v'; }

long long ystb_strtoll(const char *s, char **end, int base) {
	const char *p = s;
	int neg = 0, any = 0;
	unsigned long long v = 0;
	while (ystb_space(*p)) p++;
	if (*p == '+' || *p == '-') neg = *p++ == '-';
	if (base == 0) base = 10;
	for (int d; (d = ystb_digit(*p, base)) >= 0; p++) {
		any = 1;
		if (v < 0x0FFFFFFFFFFFFFFFull) v = v * (unsigned)base + (unsigned)d;
	}
	if (end) *end = (char *)(any ? p : s);
	return neg ? -(long long)v : (long long)v;
}

long ystb_strtol(const char *s, char **end, int base) {
	long long v = ystb_strtoll(s, end, base);
	if (v > 0x7FFFFFFFL) return 0x7FFFFFFFL;
	if (v < -0x7FFFFFFFL - 1) return -0x7FFFFFFFL - 1;
	return (long)v;
}

/* Literal characters, whitespace (any run), %u, %d, %x and %Nx. */
int ystb_sscanf(const char *s, const char *fmt, ...) {
	va_list ap;
	int n = 0;
	va_start(ap, fmt);
	while (*fmt) {
		if (ystb_space(*fmt)) {
			while (ystb_space(*s)) s++;
			fmt++;
			continue;
		}
		if (*fmt != '%') {
			if (*s != *fmt) break;
			s++, fmt++;
			continue;
		}
		fmt++;
		int width = 0;
		while (*fmt >= '0' && *fmt <= '9') width = width * 10 + (*fmt++ - '0');
		char conv = *fmt++;
		int base = conv == 'x' ? 16 : 10;
		if (conv != 'x') while (ystb_space(*s)) s++;
		int neg = 0;
		if (conv == 'd' && (*s == '-' || *s == '+')) neg = *s++ == '-';
		unsigned v = 0;
		int got = 0;
		for (int d; (width == 0 || got < width) && (d = ystb_digit(*s, base)) >= 0; s++, got++) v = v * (unsigned)base + (unsigned)d;
		if (got == 0) break;
		if (conv == 'd') *va_arg(ap, int *) = neg ? -(int)v : (int)v;
		else *va_arg(ap, unsigned *) = v;
		n++;
	}
	va_end(ap);
	return n;
}

char *ystb_strchr(const char *s, int c) {
	for (;; s++) {
		if (*s == (char)c) return (char *)s;
		if (!*s) return 0;
	}
}

char *ystb_strstr(const char *h, const char *n) {
	size_t k = ystb_strlen(n);
	if (k == 0) return (char *)h;
	for (; *h; h++) if (ystb_strncmp(h, n, k) == 0) return (char *)h;
	return 0;
}

char *ystb_strncpy(char *d, const char *s, size_t n) {
	size_t i = 0;
	for (; i < n && s[i]; i++) d[i] = s[i];
	for (; i < n; i++) d[i] = 0;
	return d;
}

/* Heap sort: no recursion, no extra memory. */
static void ystb_swap(char *a, char *b, size_t size) {
	while (size--) {
		char t = *a;
		*a++ = *b;
		*b++ = t;
	}
}

static void ystb_sift(char *base, size_t size, size_t root, size_t n, int (*cmp)(const void *, const void *)) {
	for (;;) {
		size_t child = 2 * root + 1;
		if (child >= n) return;
		if (child + 1 < n && cmp(base + child * size, base + (child + 1) * size) < 0) child++;
		if (cmp(base + root * size, base + child * size) >= 0) return;
		ystb_swap(base + root * size, base + child * size, size);
		root = child;
	}
}

void ystb_qsort(void *base, size_t n, size_t size, int (*cmp)(const void *, const void *)) {
	char *b = (char *)base;
	if (n < 2) return;
	for (size_t i = n / 2; i-- > 0;) ystb_sift(b, size, i, n, cmp);
	for (size_t end = n - 1; end > 0; end--) {
		ystb_swap(b, b + end * size, size);
		ystb_sift(b, size, 0, end, cmp);
	}
}
