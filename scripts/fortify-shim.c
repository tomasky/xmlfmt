#include <string.h>
#include <stdarg.h>
#include <stdio.h>
void *__memcpy_chk(void *d, const void *s, size_t n, size_t dn) { (void)dn; return memcpy(d, s, n); }
void *__memmove_chk(void *d, const void *s, size_t n, size_t dn) { (void)dn; return memmove(d, s, n); }
void *__memset_chk(void *d, int c, size_t n, size_t dn) { (void)dn; return memset(d, c, n); }
char *__strcpy_chk(char *d, const char *s, size_t dn) { (void)dn; return strcpy(d, s); }
char *__stpcpy_chk(char *d, const char *s, size_t dn) { (void)dn; return stpcpy(d, s); }
char *__strcat_chk(char *d, const char *s, size_t dn) { (void)dn; return strcat(d, s); }
char *__strncpy_chk(char *d, const char *s, size_t n, size_t dn) { (void)dn; return strncpy(d, s, n); }
char *__strncat_chk(char *d, const char *s, size_t n, size_t dn) { (void)dn; return strncat(d, s, n); }
int __sprintf_chk(char *s, int flag, size_t slen, const char *fmt, ...) { (void)flag; (void)slen; va_list ap; va_start(ap, fmt); int r = vsprintf(s, fmt, ap); va_end(ap); return r; }
int __vsprintf_chk(char *s, int flag, size_t slen, const char *fmt, va_list ap) { (void)flag; (void)slen; return vsprintf(s, fmt, ap); }
int __snprintf_chk(char *s, size_t n, int flag, size_t slen, const char *fmt, ...) { (void)flag; (void)slen; va_list ap; va_start(ap, fmt); int r = vsnprintf(s, n, fmt, ap); va_end(ap); return r; }
int __vsnprintf_chk(char *s, size_t n, int flag, size_t slen, const char *fmt, va_list ap) { (void)flag; (void)slen; return vsnprintf(s, n, fmt, ap); }
int __printf_chk(int flag, const char *fmt, ...) { (void)flag; va_list ap; va_start(ap, fmt); int r = vprintf(fmt, ap); va_end(ap); return r; }
int __vprintf_chk(int flag, const char *fmt, va_list ap) { (void)flag; return vprintf(fmt, ap); }
int __fprintf_chk(FILE *f, int flag, const char *fmt, ...) { (void)flag; va_list ap; va_start(ap, fmt); int r = vfprintf(f, fmt, ap); va_end(ap); return r; }
int __vfprintf_chk(FILE *f, int flag, const char *fmt, va_list ap) { (void)flag; return vfprintf(f, fmt, ap); }
