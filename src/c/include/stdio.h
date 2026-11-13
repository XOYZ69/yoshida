#ifndef YSTB_STDIO_H
#define YSTB_STDIO_H
/* No files: the libraries' file functions (unused by yoshida) fail. */
typedef struct ystb_file FILE;
#define SEEK_SET 0
#define SEEK_END 2
#define fopen(name, mode) ((FILE *)0)
#define fclose(fp) 0
#define fread(p, size, n, fp) 0
#define fseek(fp, off, whence) (-1)
#define ftell(fp) (-1L)
#define fprintf(fp, ...) 0
int ystb_sscanf(const char *s, const char *fmt, ...);
#define sscanf ystb_sscanf
#endif
